*&---------------------------------------------------------------------*
*& Report Z_PO_INTELLIGENCE_ANALYZER
*& Purchase Order Intelligence Analyzer
*&---------------------------------------------------------------------*
REPORT ZDJ_PURCHASE_ORDER_ALV.

TABLES: ekko, ekpo, lfa1, mara.
TYPE-POOLS: slis, icon.

CONSTANTS:
  gc_threshold_price  TYPE p DECIMALS 2 VALUE '20.00',
  gc_threshold_vendor TYPE p DECIMALS 2 VALUE '60.00',
  gc_threshold_volume TYPE p DECIMALS 2 VALUE '2.00'.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS:     p_bukrs TYPE ekko-bukrs.
  SELECT-OPTIONS: s_bedat FOR ekko-bedat OBLIGATORY,
                  s_lifnr FOR ekko-lifnr,
                  s_matnr FOR ekpo-matnr.
SELECTION-SCREEN END OF BLOCK b1.

TYPES: BEGIN OF ty_po,
         ebeln        TYPE ekko-ebeln,
         bedat        TYPE ekko-bedat,
         lifnr        TYPE ekko-lifnr,
         name1        TYPE lfa1-name1,
         matnr        TYPE ekpo-matnr,
         maktx        TYPE makt-maktx,
         ebelp        TYPE ekpo-ebelp,
         menge        TYPE ekpo-menge,
         meins        TYPE ekpo-meins,
         price        TYPE ekpo-netpr,
         prev_price   TYPE ekpo-netpr,
         price_change TYPE p DECIMALS 2,
         warning      TYPE string,
         icon         TYPE icon_d,
       END OF ty_po.

DATA: gt_po   TYPE TABLE OF ty_po,
      gs_po   TYPE ty_po,
      gt_fcat TYPE slis_t_fieldcat_alv,
      gs_fcat TYPE slis_fieldcat_alv,
      gs_layo TYPE slis_layout_alv.

*INITIALIZATION.
* write 'PO Intelligence Analyzer'.

START-OF-SELECTION.
  PERFORM get_data.
  PERFORM analyze_data.
  PERFORM display_alv.

*&---------------------------------------------------------------------*
FORM get_data.

  DATA: lt_ekko  TYPE TABLE OF ekko,
        ls_ekko  TYPE ekko,
        ls_ekpo  TYPE ekpo,
        ls_lfa1  TYPE lfa1,
        ls_makt  TYPE makt,
        ls_po    TYPE ty_po.

  DATA: lv_ebeln TYPE ekpo-ebeln.

  " Step 1: Get PO Headers
  SELECT ebeln, bedat, lifnr ,bukrs
    FROM ekko
    INTO CORRESPONDING FIELDS OF TABLE @lt_ekko
    WHERE bukrs = @p_bukrs
      AND bedat IN @s_bedat.

  IF lt_ekko IS INITIAL.
    MESSAGE 'No PO headers found. Check Company Code and Date.' TYPE 'I'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  " Step 2: Loop headers and fetch items
  LOOP AT lt_ekko INTO ls_ekko.

    lv_ebeln = ls_ekko-ebeln.

    " Fetch ALL items for this PO - no filters at all
    SELECT *
      FROM ekpo
      INTO ls_ekpo
      WHERE ebeln = lv_ebeln.

      CLEAR ls_po.
      ls_po-ebeln = ls_ekko-ebeln.
      ls_po-bedat = ls_ekko-bedat.
      ls_po-lifnr = ls_ekko-lifnr.
      ls_po-ebelp = ls_ekpo-ebelp.
      ls_po-matnr = ls_ekpo-matnr.
      ls_po-menge = ls_ekpo-menge.
      ls_po-meins = ls_ekpo-meins.
      ls_po-price = ls_ekpo-netpr.

      " Vendor name
      SELECT SINGLE name1 FROM lfa1
        INTO @ls_po-name1
        WHERE lifnr = @ls_ekko-lifnr.

      " Material description
      SELECT SINGLE maktx FROM makt
        INTO @ls_po-maktx
        WHERE matnr = @ls_ekpo-matnr
          AND spras = @sy-langu.

      APPEND ls_po TO gt_po.

    ENDSELECT.

  ENDLOOP.

*  " Optional filters
*  IF s_lifnr[] IS NOT INITIAL.
*    DELETE gt_po WHERE lifnr NOT IN s_lifnr.
*  ENDIF.
*
*  IF s_matnr[] IS NOT INITIAL.
*    DELETE gt_po WHERE matnr NOT IN s_matnr.
*  ENDIF.

*  IF gt_po IS INITIAL.
*    MESSAGE 'Items exist but filtered out. Try without Vendor/Material filters.' TYPE 'I'.
*    LEAVE LIST-PROCESSING.
*  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
FORM analyze_data.

  DATA: lv_prev_price TYPE ekpo-netpr,
        lv_avg_qty    TYPE p DECIMALS 3,
        lv_total_pos  TYPE i,
        lv_vendor_pos TYPE i,
        lv_ratio      TYPE p DECIMALS 2,
        lv_day        TYPE i,
        lv_po_date    TYPE d.

  LOOP AT gt_po INTO gs_po.

    CLEAR: lv_prev_price, lv_avg_qty, lv_total_pos,
           lv_vendor_pos, lv_ratio, lv_day.

    " RULE 1: PRICE SPIKE
    SELECT SINGLE MAX( netpr ) FROM ekpo
      INTO @lv_prev_price
      WHERE matnr = @gs_po-matnr
        AND ebeln <> @gs_po-ebeln
        AND netpr > 0.

    gs_po-prev_price = lv_prev_price.
    IF lv_prev_price > 0.
      gs_po-price_change =
        ( ( gs_po-price - lv_prev_price ) / lv_prev_price ) * 100.
      IF gs_po-price_change > gc_threshold_price.
        gs_po-warning = 'PRICE SPIKE'.
        gs_po-icon    = icon_led_red.
      ENDIF.
    ENDIF.

    " RULE 2: VOLUME INCREASE
    SELECT AVG( menge ) FROM ekpo INTO @lv_avg_qty
      WHERE matnr = @gs_po-matnr
        AND ebeln <> @gs_po-ebeln
        AND menge > 0.

    IF lv_avg_qty > 0 AND gs_po-menge > ( lv_avg_qty * gc_threshold_volume ).
      IF gs_po-icon IS INITIAL.
        gs_po-warning = 'UNUSUAL PURCHASE VOLUME'.
        gs_po-icon    = icon_led_yellow.
      ENDIF.
    ENDIF.

    " RULE 3: VENDOR DEPENDENCY
    SELECT COUNT(*) FROM ekpo AS b
      INNER JOIN ekko AS a ON a~ebeln = b~ebeln
      INTO @lv_total_pos
      WHERE b~matnr = @gs_po-matnr.

    SELECT COUNT(*) FROM ekpo AS b
      INNER JOIN ekko AS a ON a~ebeln = b~ebeln
      INTO @lv_vendor_pos
      WHERE b~matnr = @gs_po-matnr
        AND a~lifnr = @gs_po-lifnr.

    IF lv_total_pos > 0.
      lv_ratio = ( lv_vendor_pos * 100 ) / lv_total_pos.
      IF lv_ratio > gc_threshold_vendor AND gs_po-icon IS INITIAL.
        gs_po-warning = 'HIGH VENDOR DEPENDENCY'.
        gs_po-icon    = icon_led_yellow.
      ENDIF.
    ENDIF.

    " CREATIVITY RULE: WEEKEND PO DETECTION
    lv_po_date = gs_po-bedat.
    lv_day = lv_po_date MOD 7.
    IF lv_day = 6 OR lv_day = 0.
      IF gs_po-icon IS INITIAL.
        gs_po-warning = 'WEEKEND PO CREATED'.
        gs_po-icon    = icon_led_yellow.
      ELSE.
        CONCATENATE gs_po-warning ' | WEEKEND PO'
          INTO gs_po-warning SEPARATED BY space.
      ENDIF.
    ENDIF.

    " DEFAULT GREEN
    IF gs_po-icon IS INITIAL.
      gs_po-icon = icon_led_green.
    ENDIF.

    MODIFY gt_po FROM gs_po.

  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
FORM build_fcat.

  CLEAR gt_fcat.

  CLEAR gs_fcat.
  gs_fcat-col_pos = 1. gs_fcat-fieldname = 'ICON'.
  gs_fcat-seltext_m = 'Status'. gs_fcat-icon = 'X'.
  gs_fcat-outputlen = 5. gs_fcat-just = 'C'.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 2. gs_fcat-fieldname = 'EBELN'.
  gs_fcat-seltext_m = 'PO Number'. gs_fcat-outputlen = 12.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 3. gs_fcat-fieldname = 'BEDAT'.
  gs_fcat-seltext_m = 'PO Date'. gs_fcat-outputlen = 10.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 4. gs_fcat-fieldname = 'MATNR'.
  gs_fcat-seltext_m = 'Material'. gs_fcat-outputlen = 18.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 5. gs_fcat-fieldname = 'MAKTX'.
  gs_fcat-seltext_m = 'Description'. gs_fcat-outputlen = 30.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 6. gs_fcat-fieldname = 'LIFNR'.
  gs_fcat-seltext_m = 'Vendor No'. gs_fcat-outputlen = 10.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 7. gs_fcat-fieldname = 'NAME1'.
  gs_fcat-seltext_m = 'Vendor Name'. gs_fcat-outputlen = 25.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 8. gs_fcat-fieldname = 'MENGE'.
  gs_fcat-seltext_m = 'Qty'. gs_fcat-outputlen = 12. gs_fcat-just = 'R'.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 9. gs_fcat-fieldname = 'MEINS'.
  gs_fcat-seltext_m = 'UoM'. gs_fcat-outputlen = 6.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 10. gs_fcat-fieldname = 'PRICE'.
  gs_fcat-seltext_m = 'Current Price'. gs_fcat-outputlen = 14.
  gs_fcat-just = 'R'. APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 11. gs_fcat-fieldname = 'PREV_PRICE'.
  gs_fcat-seltext_m = 'Prev Price'. gs_fcat-outputlen = 14.
  gs_fcat-just = 'R'. APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 12. gs_fcat-fieldname = 'PRICE_CHANGE'.
  gs_fcat-seltext_m = 'Change %'. gs_fcat-outputlen = 10.
  gs_fcat-just = 'R'. APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 13. gs_fcat-fieldname = 'WARNING'.
  gs_fcat-seltext_m = 'Warning'. gs_fcat-outputlen = 35.
  APPEND gs_fcat TO gt_fcat.

ENDFORM.

*&---------------------------------------------------------------------*
FORM display_alv.

  PERFORM build_fcat.

  CLEAR gs_layo.
  gs_layo-colwidth_optimize = abap_true.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      i_callback_program       = sy-repid
      i_callback_pf_status_set = 'SET_PF_STATUS'
      i_callback_user_command  = 'USER_COMMAND'
      i_callback_top_of_page   = 'TOP_OF_PAGE'
      is_layout                = gs_layo
      it_fieldcat              = gt_fcat
      i_save                   = 'A'
    TABLES
      t_outtab                 = gt_po
    EXCEPTIONS
      program_error            = 1
      OTHERS                   = 2.

ENDFORM.

*&---------------------------------------------------------------------*
FORM top_of_page.

  DATA: lt_header TYPE slis_t_listheader,
        ls_header TYPE slis_listheader,
        lv_count  TYPE char10,
        lv_warn   TYPE char10.

  ls_header-typ  = 'H'.
  ls_header-info = 'Purchase Order Intelligence Analyzer'.
  APPEND ls_header TO lt_header.

  CLEAR ls_header.
  ls_header-typ = 'S'.
  CONCATENATE 'Company Code:' p_bukrs
    INTO ls_header-info SEPARATED BY space.
  APPEND ls_header TO lt_header.

  CLEAR ls_header.
  ls_header-typ = 'S'.
  CONCATENATE 'Date Range:' s_bedat-low 'to' s_bedat-high
    INTO ls_header-info SEPARATED BY space.
  APPEND ls_header TO lt_header.

  DESCRIBE TABLE gt_po LINES lv_count.
*  LOOP AT gt_po INTO gs_po WHERE icon <> icon_green_light.
*    lv_warn = lv_warn + 1.
*  ENDLOOP.

  CLEAR ls_header.
  ls_header-typ = 'S'.
  CONCATENATE 'Total PO Lines:' lv_count
*  ' | Warnings:' lv_warn
    INTO ls_header-info SEPARATED BY space.
  APPEND ls_header TO lt_header.

  CALL FUNCTION 'REUSE_ALV_COMMENTARY_WRITE'
    EXPORTING
      it_list_commentary = lt_header.

ENDFORM.

*&---------------------------------------------------------------------*

FORM user_command USING r_ucomm     LIKE sy-ucomm
                        rs_selfield TYPE slis_selfield.

  IF r_ucomm = '&IC1'.

    READ TABLE gt_po INTO gs_po INDEX rs_selfield-tabindex.

    IF sy-subrc = 0.

      " Double-click on PO Number → ME23N
      IF rs_selfield-fieldname = 'EBELN'.
        IF gs_po-ebeln IS NOT INITIAL.
          SET PARAMETER ID 'BES' FIELD gs_po-ebeln.
          CALL TRANSACTION 'ME23N' AND SKIP FIRST SCREEN.
        ENDIF.

      " Double-click on ANY other field → Price History
      ELSE.
*        IF gs_po-matnr IS NOT INITIAL.
*          PERFORM show_price_history USING gs_po-matnr gs_po-name1.
*        ENDIF.

         IF gs_po-matnr IS NOT INITIAL.
           PERFORM show_price_graph USING gs_po-matnr.
         ENDIF.
      ENDIF.

    ENDIF.

  " RISK button
  ELSEIF r_ucomm = 'RISK'.
    PERFORM show_top5_risk_vendors.

  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
FORM set_pf_status USING rt_extab TYPE slis_t_extab.
  SET PF-STATUS 'ZRISK' EXCLUDING rt_extab.
ENDFORM.

*&---------------------------------------------------------------------*
FORM show_top5_risk_vendors.

  TYPES: BEGIN OF ty_vendor_risk,
           lifnr       TYPE ekko-lifnr,
           name1       TYPE lfa1-name1,
           alert_count TYPE i,
         END OF ty_vendor_risk.

  DATA: lt_risk TYPE TABLE OF ty_vendor_risk,
        ls_risk TYPE ty_vendor_risk,
        lt_fcat TYPE slis_t_fieldcat_alv,
        ls_fcat TYPE slis_fieldcat_alv,
        ls_layo TYPE slis_layout_alv.

  LOOP AT gt_po INTO gs_po WHERE icon <> icon_green_light.
    READ TABLE lt_risk INTO ls_risk WITH KEY lifnr = gs_po-lifnr.
    IF sy-subrc = 0.
      ls_risk-alert_count = ls_risk-alert_count + 1.
      MODIFY lt_risk FROM ls_risk
        TRANSPORTING alert_count WHERE lifnr = gs_po-lifnr.
    ELSE.
      ls_risk-lifnr       = gs_po-lifnr.
      ls_risk-name1       = gs_po-name1.
      ls_risk-alert_count = 1.
      APPEND ls_risk TO lt_risk.
    ENDIF.
  ENDLOOP.

  SORT lt_risk BY alert_count DESCENDING.
  DELETE lt_risk FROM 6.

  IF lt_risk IS INITIAL.
    MESSAGE 'No risk vendors found.' TYPE 'I'.
    RETURN.
  ENDIF.

  CLEAR ls_fcat.
  ls_fcat-col_pos = 1. ls_fcat-fieldname = 'LIFNR'.
  ls_fcat-seltext_m = 'Vendor No'. ls_fcat-outputlen = 12.
  APPEND ls_fcat TO lt_fcat.

  CLEAR ls_fcat.
  ls_fcat-col_pos = 2. ls_fcat-fieldname = 'NAME1'.
  ls_fcat-seltext_m = 'Vendor Name'. ls_fcat-outputlen = 30.
  APPEND ls_fcat TO lt_fcat.

  CLEAR ls_fcat.
  ls_fcat-col_pos = 3. ls_fcat-fieldname = 'ALERT_COUNT'.
  ls_fcat-seltext_m = 'Number of Alerts'. ls_fcat-outputlen = 15.
  ls_fcat-just = 'R'.
  APPEND ls_fcat TO lt_fcat.

  ls_layo-colwidth_optimize = abap_true.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      i_callback_program    = sy-repid
      is_layout             = ls_layo
      it_fieldcat           = lt_fcat
      i_grid_title          = 'Top 5 Risk Vendors - Sorted by Alert Count'
      i_screen_start_column = 10
      i_screen_start_line   = 5
      i_screen_end_column   = 90
      i_screen_end_line     = 20
    TABLES
      t_outtab              = lt_risk
    EXCEPTIONS
      program_error         = 1
      OTHERS                = 2.

ENDFORM.
*&---------------------------------------------------------------------*
*FORM show_price_history USING pv_matnr TYPE ekpo-matnr
*                              pv_name1 TYPE lfa1-name1.
*
*  TYPES: BEGIN OF ty_hist,
*           ebeln TYPE ekpo-ebeln,
*           bedat TYPE ekko-bedat,
*           lifnr TYPE ekko-lifnr,
*           name1 TYPE lfa1-name1,
*           menge TYPE ekpo-menge,
*           meins TYPE ekpo-meins,
*           netpr TYPE ekpo-netpr,
*         END OF ty_hist.
*
*  DATA: lt_hist  TYPE TABLE OF ty_hist,
*        ls_hist  TYPE ty_hist,
*        lt_fcat  TYPE slis_t_fieldcat_alv,
*        ls_fcat  TYPE slis_fieldcat_alv,
*        ls_layo  TYPE slis_layout_alv,
*        lv_title TYPE char70.
*
*  " Fetch all price history for this material
*  SELECT b~ebeln, a~bedat, a~lifnr,
*         b~menge, b~meins, b~netpr
*    FROM ekko AS a
*    INNER JOIN ekpo AS b ON a~ebeln = b~ebeln
*    INTO CORRESPONDING FIELDS OF TABLE @lt_hist
*    WHERE b~matnr = @pv_matnr
*    ORDER BY a~bedat DESCENDING.
*
*  " Get vendor name for each row
*  LOOP AT lt_hist INTO ls_hist.
*    SELECT SINGLE name1 FROM lfa1
*      INTO @ls_hist-name1
*      WHERE lifnr = @ls_hist-lifnr.
*    MODIFY lt_hist FROM ls_hist.
*  ENDLOOP.
*
*  IF lt_hist IS INITIAL.
*    MESSAGE 'No price history found for this material.' TYPE 'I'.
*    RETURN.
*  ENDIF.
*
*  " Build field catalog
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 1. ls_fcat-fieldname = 'EBELN'.
*  ls_fcat-seltext_m = 'PO Number'. ls_fcat-outputlen = 12.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 2. ls_fcat-fieldname = 'BEDAT'.
*  ls_fcat-seltext_m = 'PO Date'. ls_fcat-outputlen = 10.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 3. ls_fcat-fieldname = 'LIFNR'.
*  ls_fcat-seltext_m = 'Vendor No'. ls_fcat-outputlen = 12.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 4. ls_fcat-fieldname = 'NAME1'.
*  ls_fcat-seltext_m = 'Vendor Name'. ls_fcat-outputlen = 25.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 5. ls_fcat-fieldname = 'MENGE'.
*  ls_fcat-seltext_m = 'Quantity'. ls_fcat-outputlen = 12.
*  ls_fcat-just = 'R'. APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 6. ls_fcat-fieldname = 'MEINS'.
*  ls_fcat-seltext_m = 'UoM'. ls_fcat-outputlen = 6.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 7. ls_fcat-fieldname = 'NETPR'.
*  ls_fcat-seltext_m = 'Price'. ls_fcat-outputlen = 14.
*  ls_fcat-just = 'R'. APPEND ls_fcat TO lt_fcat.
*
*  " Layout
*  ls_layo-colwidth_optimize = abap_true.
*  ls_layo-zebra             = abap_true.
*
*lv_title = 'Price History for Material: '.
*CONCATENATE lv_title pv_matnr INTO lv_title.
*
*  " Show as popup
*  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
*    EXPORTING
*      i_callback_program    = sy-repid
*      is_layout             = ls_layo
*      it_fieldcat           = lt_fcat
*      i_grid_title          = lv_title
*      i_screen_start_column = 5
*      i_screen_start_line   = 3
*      i_screen_end_column   = 110
*      i_screen_end_line     = 25
*    TABLES
*      t_outtab              = lt_hist
*    EXCEPTIONS
*      program_error         = 1
*      OTHERS                = 2.
*
*ENDFORM.






*FORM show_price_graph USING pv_matnr TYPE ekpo-matnr.
*
*  TYPES: BEGIN OF ty_hist,
*           bedat TYPE ekko-bedat,
*           netpr TYPE ekpo-netpr,
*         END OF ty_hist.
*
*  DATA: lt_hist TYPE TABLE OF ty_hist,
*        ls_hist TYPE ty_hist.
*
*  DATA: lt_graph TYPE TABLE OF gprval,
*        ls_graph TYPE gprval.
*
*  DATA: lt_opts TYPE TABLE OF char80.
*
*  SELECT a~bedat
*         b~netpr
*    FROM ekko AS a
*    INNER JOIN ekpo AS b
*      ON a~ebeln = b~ebeln
*    INTO TABLE lt_hist
*    WHERE b~matnr = pv_matnr
*    ORDER BY a~bedat.
*
*  IF lt_hist IS INITIAL.
*    MESSAGE 'No price history found.' TYPE 'I'.
*    RETURN.
*  ENDIF.
*
*  LOOP AT lt_hist INTO ls_hist.
*
*    CLEAR ls_graph.
*
*    ls_graph-rowtxt = ls_hist-bedat.
*    ls_graph-val1   = ls_hist-netpr.
*
*    APPEND ls_graph TO lt_graph.
**    APPEND 'SET P2TYPE LINE' TO lt_opts.
*
*  ENDLOOP.
*
*  CALL FUNCTION 'GRAPH_MATRIX_3D'
*    EXPORTING
*      col1 = 'Price'
*      dim1 = 'Price'
*      dim2 = 'Date'
*      titl = 'Material Price Trend'
*    TABLES
*      data = lt_graph
*      opts = lt_opts
*    EXCEPTIONS
*      OTHERS = 1.
*
*ENDFORM.






FORM show_price_graph USING pv_matnr TYPE ekpo-matnr.

  TYPES: BEGIN OF ty_hist,
           bedat TYPE ekko-bedat,
           netpr TYPE ekpo-netpr,
         END OF ty_hist.

  DATA: lt_hist TYPE TABLE OF ty_hist,
        ls_hist TYPE ty_hist.

  DATA: lt_graph TYPE TABLE OF gprval,
        ls_graph TYPE gprval.

  DATA: lt_opts TYPE TABLE OF char80,
        lv_opt  TYPE char80.

  SELECT a~bedat
         b~netpr
    FROM ekko AS a
    INNER JOIN ekpo AS b
      ON a~ebeln = b~ebeln
    INTO TABLE lt_hist
    WHERE b~matnr = pv_matnr
    ORDER BY a~bedat.

  IF lt_hist IS INITIAL.
    MESSAGE 'No price history found.' TYPE 'I'.
    RETURN.
  ENDIF.

  LOOP AT lt_hist INTO ls_hist.

    CLEAR ls_graph.

    ls_graph-rowtxt = ls_hist-bedat.
    ls_graph-val1   = ls_hist-netpr.

    APPEND ls_graph TO lt_graph.

  ENDLOOP.

  lv_opt = 'P2TYPE=LINE'.
  APPEND lv_opt TO lt_opts.

  CALL FUNCTION 'GRAPH_MATRIX_3D'
    EXPORTING
      col1 = 'Price'
      dim1 = 'Price'
      dim2 = 'Date'
      titl = 'Material Price Trend'
    TABLES
      data = lt_graph
      opts = lt_opts
    EXCEPTIONS
      OTHERS = 1.

ENDFORM.*&---------------------------------------------------------------------*
*& Report Z_PO_INTELLIGENCE_ANALYZER
*& Purchase Order Intelligence Analyzer
*&---------------------------------------------------------------------*
REPORT ZDJ_PURCHASE_ORDER_ALV.

TABLES: ekko, ekpo, lfa1, mara.
TYPE-POOLS: slis, icon.

CONSTANTS:
  gc_threshold_price  TYPE p DECIMALS 2 VALUE '20.00',
  gc_threshold_vendor TYPE p DECIMALS 2 VALUE '60.00',
  gc_threshold_volume TYPE p DECIMALS 2 VALUE '2.00'.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS:     p_bukrs TYPE ekko-bukrs.
  SELECT-OPTIONS: s_bedat FOR ekko-bedat OBLIGATORY,
                  s_lifnr FOR ekko-lifnr,
                  s_matnr FOR ekpo-matnr.
SELECTION-SCREEN END OF BLOCK b1.

TYPES: BEGIN OF ty_po,
         ebeln        TYPE ekko-ebeln,
         bedat        TYPE ekko-bedat,
         lifnr        TYPE ekko-lifnr,
         name1        TYPE lfa1-name1,
         matnr        TYPE ekpo-matnr,
         maktx        TYPE makt-maktx,
         ebelp        TYPE ekpo-ebelp,
         menge        TYPE ekpo-menge,
         meins        TYPE ekpo-meins,
         price        TYPE ekpo-netpr,
         prev_price   TYPE ekpo-netpr,
         price_change TYPE p DECIMALS 2,
         warning      TYPE string,
         icon         TYPE icon_d,
       END OF ty_po.

DATA: gt_po   TYPE TABLE OF ty_po,
      gs_po   TYPE ty_po,
      gt_fcat TYPE slis_t_fieldcat_alv,
      gs_fcat TYPE slis_fieldcat_alv,
      gs_layo TYPE slis_layout_alv.

*INITIALIZATION.
* write 'PO Intelligence Analyzer'.

START-OF-SELECTION.
  PERFORM get_data.
  PERFORM analyze_data.
  PERFORM display_alv.

*&---------------------------------------------------------------------*
FORM get_data.

  DATA: lt_ekko  TYPE TABLE OF ekko,
        ls_ekko  TYPE ekko,
        ls_ekpo  TYPE ekpo,
        ls_lfa1  TYPE lfa1,
        ls_makt  TYPE makt,
        ls_po    TYPE ty_po.

  DATA: lv_ebeln TYPE ekpo-ebeln.

  " Step 1: Get PO Headers
  SELECT ebeln, bedat, lifnr ,bukrs
    FROM ekko
    INTO CORRESPONDING FIELDS OF TABLE @lt_ekko
    WHERE bukrs = @p_bukrs
      AND bedat IN @s_bedat.

  IF lt_ekko IS INITIAL.
    MESSAGE 'No PO headers found. Check Company Code and Date.' TYPE 'I'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  " Step 2: Loop headers and fetch items
  LOOP AT lt_ekko INTO ls_ekko.

    lv_ebeln = ls_ekko-ebeln.

    " Fetch ALL items for this PO - no filters at all
    SELECT *
      FROM ekpo
      INTO ls_ekpo
      WHERE ebeln = lv_ebeln.

      CLEAR ls_po.
      ls_po-ebeln = ls_ekko-ebeln.
      ls_po-bedat = ls_ekko-bedat.
      ls_po-lifnr = ls_ekko-lifnr.
      ls_po-ebelp = ls_ekpo-ebelp.
      ls_po-matnr = ls_ekpo-matnr.
      ls_po-menge = ls_ekpo-menge.
      ls_po-meins = ls_ekpo-meins.
      ls_po-price = ls_ekpo-netpr.

      " Vendor name
      SELECT SINGLE name1 FROM lfa1
        INTO @ls_po-name1
        WHERE lifnr = @ls_ekko-lifnr.

      " Material description
      SELECT SINGLE maktx FROM makt
        INTO @ls_po-maktx
        WHERE matnr = @ls_ekpo-matnr
          AND spras = @sy-langu.

      APPEND ls_po TO gt_po.

    ENDSELECT.

  ENDLOOP.

*  " Optional filters
*  IF s_lifnr[] IS NOT INITIAL.
*    DELETE gt_po WHERE lifnr NOT IN s_lifnr.
*  ENDIF.
*
*  IF s_matnr[] IS NOT INITIAL.
*    DELETE gt_po WHERE matnr NOT IN s_matnr.
*  ENDIF.

*  IF gt_po IS INITIAL.
*    MESSAGE 'Items exist but filtered out. Try without Vendor/Material filters.' TYPE 'I'.
*    LEAVE LIST-PROCESSING.
*  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
FORM analyze_data.

  DATA: lv_prev_price TYPE ekpo-netpr,
        lv_avg_qty    TYPE p DECIMALS 3,
        lv_total_pos  TYPE i,
        lv_vendor_pos TYPE i,
        lv_ratio      TYPE p DECIMALS 2,
        lv_day        TYPE i,
        lv_po_date    TYPE d.

  LOOP AT gt_po INTO gs_po.

    CLEAR: lv_prev_price, lv_avg_qty, lv_total_pos,
           lv_vendor_pos, lv_ratio, lv_day.

    " RULE 1: PRICE SPIKE
    SELECT SINGLE MAX( netpr ) FROM ekpo
      INTO @lv_prev_price
      WHERE matnr = @gs_po-matnr
        AND ebeln <> @gs_po-ebeln
        AND netpr > 0.

    gs_po-prev_price = lv_prev_price.
    IF lv_prev_price > 0.
      gs_po-price_change =
        ( ( gs_po-price - lv_prev_price ) / lv_prev_price ) * 100.
      IF gs_po-price_change > gc_threshold_price.
        gs_po-warning = 'PRICE SPIKE'.
        gs_po-icon    = icon_led_red.
      ENDIF.
    ENDIF.

    " RULE 2: VOLUME INCREASE
    SELECT AVG( menge ) FROM ekpo INTO @lv_avg_qty
      WHERE matnr = @gs_po-matnr
        AND ebeln <> @gs_po-ebeln
        AND menge > 0.

    IF lv_avg_qty > 0 AND gs_po-menge > ( lv_avg_qty * gc_threshold_volume ).
      IF gs_po-icon IS INITIAL.
        gs_po-warning = 'UNUSUAL PURCHASE VOLUME'.
        gs_po-icon    = icon_led_yellow.
      ENDIF.
    ENDIF.

    " RULE 3: VENDOR DEPENDENCY
    SELECT COUNT(*) FROM ekpo AS b
      INNER JOIN ekko AS a ON a~ebeln = b~ebeln
      INTO @lv_total_pos
      WHERE b~matnr = @gs_po-matnr.

    SELECT COUNT(*) FROM ekpo AS b
      INNER JOIN ekko AS a ON a~ebeln = b~ebeln
      INTO @lv_vendor_pos
      WHERE b~matnr = @gs_po-matnr
        AND a~lifnr = @gs_po-lifnr.

    IF lv_total_pos > 0.
      lv_ratio = ( lv_vendor_pos * 100 ) / lv_total_pos.
      IF lv_ratio > gc_threshold_vendor AND gs_po-icon IS INITIAL.
        gs_po-warning = 'HIGH VENDOR DEPENDENCY'.
        gs_po-icon    = icon_led_yellow.
      ENDIF.
    ENDIF.

    " CREATIVITY RULE: WEEKEND PO DETECTION
    lv_po_date = gs_po-bedat.
    lv_day = lv_po_date MOD 7.
    IF lv_day = 6 OR lv_day = 0.
      IF gs_po-icon IS INITIAL.
        gs_po-warning = 'WEEKEND PO CREATED'.
        gs_po-icon    = icon_led_yellow.
      ELSE.
        CONCATENATE gs_po-warning ' | WEEKEND PO'
          INTO gs_po-warning SEPARATED BY space.
      ENDIF.
    ENDIF.

    " DEFAULT GREEN
    IF gs_po-icon IS INITIAL.
      gs_po-icon = icon_led_green.
    ENDIF.

    MODIFY gt_po FROM gs_po.

  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
FORM build_fcat.

  CLEAR gt_fcat.

  CLEAR gs_fcat.
  gs_fcat-col_pos = 1. gs_fcat-fieldname = 'ICON'.
  gs_fcat-seltext_m = 'Status'. gs_fcat-icon = 'X'.
  gs_fcat-outputlen = 5. gs_fcat-just = 'C'.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 2. gs_fcat-fieldname = 'EBELN'.
  gs_fcat-seltext_m = 'PO Number'. gs_fcat-outputlen = 12.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 3. gs_fcat-fieldname = 'BEDAT'.
  gs_fcat-seltext_m = 'PO Date'. gs_fcat-outputlen = 10.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 4. gs_fcat-fieldname = 'MATNR'.
  gs_fcat-seltext_m = 'Material'. gs_fcat-outputlen = 18.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 5. gs_fcat-fieldname = 'MAKTX'.
  gs_fcat-seltext_m = 'Description'. gs_fcat-outputlen = 30.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 6. gs_fcat-fieldname = 'LIFNR'.
  gs_fcat-seltext_m = 'Vendor No'. gs_fcat-outputlen = 10.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 7. gs_fcat-fieldname = 'NAME1'.
  gs_fcat-seltext_m = 'Vendor Name'. gs_fcat-outputlen = 25.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 8. gs_fcat-fieldname = 'MENGE'.
  gs_fcat-seltext_m = 'Qty'. gs_fcat-outputlen = 12. gs_fcat-just = 'R'.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 9. gs_fcat-fieldname = 'MEINS'.
  gs_fcat-seltext_m = 'UoM'. gs_fcat-outputlen = 6.
  APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 10. gs_fcat-fieldname = 'PRICE'.
  gs_fcat-seltext_m = 'Current Price'. gs_fcat-outputlen = 14.
  gs_fcat-just = 'R'. APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 11. gs_fcat-fieldname = 'PREV_PRICE'.
  gs_fcat-seltext_m = 'Prev Price'. gs_fcat-outputlen = 14.
  gs_fcat-just = 'R'. APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 12. gs_fcat-fieldname = 'PRICE_CHANGE'.
  gs_fcat-seltext_m = 'Change %'. gs_fcat-outputlen = 10.
  gs_fcat-just = 'R'. APPEND gs_fcat TO gt_fcat.

  CLEAR gs_fcat. gs_fcat-col_pos = 13. gs_fcat-fieldname = 'WARNING'.
  gs_fcat-seltext_m = 'Warning'. gs_fcat-outputlen = 35.
  APPEND gs_fcat TO gt_fcat.

ENDFORM.

*&---------------------------------------------------------------------*
FORM display_alv.

  PERFORM build_fcat.

  CLEAR gs_layo.
  gs_layo-colwidth_optimize = abap_true.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      i_callback_program       = sy-repid
      i_callback_pf_status_set = 'SET_PF_STATUS'
      i_callback_user_command  = 'USER_COMMAND'
      i_callback_top_of_page   = 'TOP_OF_PAGE'
      is_layout                = gs_layo
      it_fieldcat              = gt_fcat
      i_save                   = 'A'
    TABLES
      t_outtab                 = gt_po
    EXCEPTIONS
      program_error            = 1
      OTHERS                   = 2.

ENDFORM.

*&---------------------------------------------------------------------*
FORM top_of_page.

  DATA: lt_header TYPE slis_t_listheader,
        ls_header TYPE slis_listheader,
        lv_count  TYPE char10,
        lv_warn   TYPE char10.

  ls_header-typ  = 'H'.
  ls_header-info = 'Purchase Order Intelligence Analyzer'.
  APPEND ls_header TO lt_header.

  CLEAR ls_header.
  ls_header-typ = 'S'.
  CONCATENATE 'Company Code:' p_bukrs
    INTO ls_header-info SEPARATED BY space.
  APPEND ls_header TO lt_header.

  CLEAR ls_header.
  ls_header-typ = 'S'.
  CONCATENATE 'Date Range:' s_bedat-low 'to' s_bedat-high
    INTO ls_header-info SEPARATED BY space.
  APPEND ls_header TO lt_header.

  DESCRIBE TABLE gt_po LINES lv_count.
*  LOOP AT gt_po INTO gs_po WHERE icon <> icon_green_light.
*    lv_warn = lv_warn + 1.
*  ENDLOOP.

  CLEAR ls_header.
  ls_header-typ = 'S'.
  CONCATENATE 'Total PO Lines:' lv_count
*  ' | Warnings:' lv_warn
    INTO ls_header-info SEPARATED BY space.
  APPEND ls_header TO lt_header.

  CALL FUNCTION 'REUSE_ALV_COMMENTARY_WRITE'
    EXPORTING
      it_list_commentary = lt_header.

ENDFORM.

*&---------------------------------------------------------------------*

FORM user_command USING r_ucomm     LIKE sy-ucomm
                        rs_selfield TYPE slis_selfield.

  IF r_ucomm = '&IC1'.

    READ TABLE gt_po INTO gs_po INDEX rs_selfield-tabindex.

    IF sy-subrc = 0.

      " Double-click on PO Number → ME23N
      IF rs_selfield-fieldname = 'EBELN'.
        IF gs_po-ebeln IS NOT INITIAL.
          SET PARAMETER ID 'BES' FIELD gs_po-ebeln.
          CALL TRANSACTION 'ME23N' AND SKIP FIRST SCREEN.
        ENDIF.

      " Double-click on ANY other field → Price History
      ELSE.
*        IF gs_po-matnr IS NOT INITIAL.
*          PERFORM show_price_history USING gs_po-matnr gs_po-name1.
*        ENDIF.

         IF gs_po-matnr IS NOT INITIAL.
           PERFORM show_price_graph USING gs_po-matnr.
         ENDIF.
      ENDIF.

    ENDIF.

  " RISK button
  ELSEIF r_ucomm = 'RISK'.
    PERFORM show_top5_risk_vendors.

  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
FORM set_pf_status USING rt_extab TYPE slis_t_extab.
  SET PF-STATUS 'ZRISK' EXCLUDING rt_extab.
ENDFORM.

*&---------------------------------------------------------------------*
FORM show_top5_risk_vendors.

  TYPES: BEGIN OF ty_vendor_risk,
           lifnr       TYPE ekko-lifnr,
           name1       TYPE lfa1-name1,
           alert_count TYPE i,
         END OF ty_vendor_risk.

  DATA: lt_risk TYPE TABLE OF ty_vendor_risk,
        ls_risk TYPE ty_vendor_risk,
        lt_fcat TYPE slis_t_fieldcat_alv,
        ls_fcat TYPE slis_fieldcat_alv,
        ls_layo TYPE slis_layout_alv.

  LOOP AT gt_po INTO gs_po WHERE icon <> icon_green_light.
    READ TABLE lt_risk INTO ls_risk WITH KEY lifnr = gs_po-lifnr.
    IF sy-subrc = 0.
      ls_risk-alert_count = ls_risk-alert_count + 1.
      MODIFY lt_risk FROM ls_risk
        TRANSPORTING alert_count WHERE lifnr = gs_po-lifnr.
    ELSE.
      ls_risk-lifnr       = gs_po-lifnr.
      ls_risk-name1       = gs_po-name1.
      ls_risk-alert_count = 1.
      APPEND ls_risk TO lt_risk.
    ENDIF.
  ENDLOOP.

  SORT lt_risk BY alert_count DESCENDING.
  DELETE lt_risk FROM 6.

  IF lt_risk IS INITIAL.
    MESSAGE 'No risk vendors found.' TYPE 'I'.
    RETURN.
  ENDIF.

  CLEAR ls_fcat.
  ls_fcat-col_pos = 1. ls_fcat-fieldname = 'LIFNR'.
  ls_fcat-seltext_m = 'Vendor No'. ls_fcat-outputlen = 12.
  APPEND ls_fcat TO lt_fcat.

  CLEAR ls_fcat.
  ls_fcat-col_pos = 2. ls_fcat-fieldname = 'NAME1'.
  ls_fcat-seltext_m = 'Vendor Name'. ls_fcat-outputlen = 30.
  APPEND ls_fcat TO lt_fcat.

  CLEAR ls_fcat.
  ls_fcat-col_pos = 3. ls_fcat-fieldname = 'ALERT_COUNT'.
  ls_fcat-seltext_m = 'Number of Alerts'. ls_fcat-outputlen = 15.
  ls_fcat-just = 'R'.
  APPEND ls_fcat TO lt_fcat.

  ls_layo-colwidth_optimize = abap_true.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      i_callback_program    = sy-repid
      is_layout             = ls_layo
      it_fieldcat           = lt_fcat
      i_grid_title          = 'Top 5 Risk Vendors - Sorted by Alert Count'
      i_screen_start_column = 10
      i_screen_start_line   = 5
      i_screen_end_column   = 90
      i_screen_end_line     = 20
    TABLES
      t_outtab              = lt_risk
    EXCEPTIONS
      program_error         = 1
      OTHERS                = 2.

ENDFORM.
*&---------------------------------------------------------------------*
*FORM show_price_history USING pv_matnr TYPE ekpo-matnr
*                              pv_name1 TYPE lfa1-name1.
*
*  TYPES: BEGIN OF ty_hist,
*           ebeln TYPE ekpo-ebeln,
*           bedat TYPE ekko-bedat,
*           lifnr TYPE ekko-lifnr,
*           name1 TYPE lfa1-name1,
*           menge TYPE ekpo-menge,
*           meins TYPE ekpo-meins,
*           netpr TYPE ekpo-netpr,
*         END OF ty_hist.
*
*  DATA: lt_hist  TYPE TABLE OF ty_hist,
*        ls_hist  TYPE ty_hist,
*        lt_fcat  TYPE slis_t_fieldcat_alv,
*        ls_fcat  TYPE slis_fieldcat_alv,
*        ls_layo  TYPE slis_layout_alv,
*        lv_title TYPE char70.
*
*  " Fetch all price history for this material
*  SELECT b~ebeln, a~bedat, a~lifnr,
*         b~menge, b~meins, b~netpr
*    FROM ekko AS a
*    INNER JOIN ekpo AS b ON a~ebeln = b~ebeln
*    INTO CORRESPONDING FIELDS OF TABLE @lt_hist
*    WHERE b~matnr = @pv_matnr
*    ORDER BY a~bedat DESCENDING.
*
*  " Get vendor name for each row
*  LOOP AT lt_hist INTO ls_hist.
*    SELECT SINGLE name1 FROM lfa1
*      INTO @ls_hist-name1
*      WHERE lifnr = @ls_hist-lifnr.
*    MODIFY lt_hist FROM ls_hist.
*  ENDLOOP.
*
*  IF lt_hist IS INITIAL.
*    MESSAGE 'No price history found for this material.' TYPE 'I'.
*    RETURN.
*  ENDIF.
*
*  " Build field catalog
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 1. ls_fcat-fieldname = 'EBELN'.
*  ls_fcat-seltext_m = 'PO Number'. ls_fcat-outputlen = 12.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 2. ls_fcat-fieldname = 'BEDAT'.
*  ls_fcat-seltext_m = 'PO Date'. ls_fcat-outputlen = 10.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 3. ls_fcat-fieldname = 'LIFNR'.
*  ls_fcat-seltext_m = 'Vendor No'. ls_fcat-outputlen = 12.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 4. ls_fcat-fieldname = 'NAME1'.
*  ls_fcat-seltext_m = 'Vendor Name'. ls_fcat-outputlen = 25.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 5. ls_fcat-fieldname = 'MENGE'.
*  ls_fcat-seltext_m = 'Quantity'. ls_fcat-outputlen = 12.
*  ls_fcat-just = 'R'. APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 6. ls_fcat-fieldname = 'MEINS'.
*  ls_fcat-seltext_m = 'UoM'. ls_fcat-outputlen = 6.
*  APPEND ls_fcat TO lt_fcat.
*
*  CLEAR ls_fcat.
*  ls_fcat-col_pos = 7. ls_fcat-fieldname = 'NETPR'.
*  ls_fcat-seltext_m = 'Price'. ls_fcat-outputlen = 14.
*  ls_fcat-just = 'R'. APPEND ls_fcat TO lt_fcat.
*
*  " Layout
*  ls_layo-colwidth_optimize = abap_true.
*  ls_layo-zebra             = abap_true.
*
*lv_title = 'Price History for Material: '.
*CONCATENATE lv_title pv_matnr INTO lv_title.
*
*  " Show as popup
*  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
*    EXPORTING
*      i_callback_program    = sy-repid
*      is_layout             = ls_layo
*      it_fieldcat           = lt_fcat
*      i_grid_title          = lv_title
*      i_screen_start_column = 5
*      i_screen_start_line   = 3
*      i_screen_end_column   = 110
*      i_screen_end_line     = 25
*    TABLES
*      t_outtab              = lt_hist
*    EXCEPTIONS
*      program_error         = 1
*      OTHERS                = 2.
*
*ENDFORM.






*FORM show_price_graph USING pv_matnr TYPE ekpo-matnr.
*
*  TYPES: BEGIN OF ty_hist,
*           bedat TYPE ekko-bedat,
*           netpr TYPE ekpo-netpr,
*         END OF ty_hist.
*
*  DATA: lt_hist TYPE TABLE OF ty_hist,
*        ls_hist TYPE ty_hist.
*
*  DATA: lt_graph TYPE TABLE OF gprval,
*        ls_graph TYPE gprval.
*
*  DATA: lt_opts TYPE TABLE OF char80.
*
*  SELECT a~bedat
*         b~netpr
*    FROM ekko AS a
*    INNER JOIN ekpo AS b
*      ON a~ebeln = b~ebeln
*    INTO TABLE lt_hist
*    WHERE b~matnr = pv_matnr
*    ORDER BY a~bedat.
*
*  IF lt_hist IS INITIAL.
*    MESSAGE 'No price history found.' TYPE 'I'.
*    RETURN.
*  ENDIF.
*
*  LOOP AT lt_hist INTO ls_hist.
*
*    CLEAR ls_graph.
*
*    ls_graph-rowtxt = ls_hist-bedat.
*    ls_graph-val1   = ls_hist-netpr.
*
*    APPEND ls_graph TO lt_graph.
**    APPEND 'SET P2TYPE LINE' TO lt_opts.
*
*  ENDLOOP.
*
*  CALL FUNCTION 'GRAPH_MATRIX_3D'
*    EXPORTING
*      col1 = 'Price'
*      dim1 = 'Price'
*      dim2 = 'Date'
*      titl = 'Material Price Trend'
*    TABLES
*      data = lt_graph
*      opts = lt_opts
*    EXCEPTIONS
*      OTHERS = 1.
*
*ENDFORM.






FORM show_price_graph USING pv_matnr TYPE ekpo-matnr.

  TYPES: BEGIN OF ty_hist,
           bedat TYPE ekko-bedat,
           netpr TYPE ekpo-netpr,
         END OF ty_hist.

  DATA: lt_hist TYPE TABLE OF ty_hist,
        ls_hist TYPE ty_hist.

  DATA: lt_graph TYPE TABLE OF gprval,
        ls_graph TYPE gprval.

  DATA: lt_opts TYPE TABLE OF char80,
        lv_opt  TYPE char80.

  SELECT a~bedat
         b~netpr
    FROM ekko AS a
    INNER JOIN ekpo AS b
      ON a~ebeln = b~ebeln
    INTO TABLE lt_hist
    WHERE b~matnr = pv_matnr
    ORDER BY a~bedat.

  IF lt_hist IS INITIAL.
    MESSAGE 'No price history found.' TYPE 'I'.
    RETURN.
  ENDIF.

  LOOP AT lt_hist INTO ls_hist.

    CLEAR ls_graph.

    ls_graph-rowtxt = ls_hist-bedat.
    ls_graph-val1   = ls_hist-netpr.

    APPEND ls_graph TO lt_graph.

  ENDLOOP.

  lv_opt = 'P2TYPE=LINE'.
  APPEND lv_opt TO lt_opts.

  CALL FUNCTION 'GRAPH_MATRIX_3D'
    EXPORTING
      col1 = 'Price'
      dim1 = 'Price'
      dim2 = 'Date'
      titl = 'Material Price Trend'
    TABLES
      data = lt_graph
      opts = lt_opts
    EXCEPTIONS
      OTHERS = 1.

ENDFORM.