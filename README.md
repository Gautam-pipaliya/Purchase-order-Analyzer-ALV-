# Purchase-order-Analyzer-ALV-
SAP ABAP Purchase Order Intelligence Analyzer — ALV-based risk detection report with price spike, vendor dependency, volume anomaly alerts and 3D price trend graph.


Purchase Order Intelligence Analyzer — SAP ABAP ALV Report
A smart SAP ABAP report that analyzes Purchase Orders and automatically flags risk patterns using business rules. Built using REUSE ALV GRID, SAP Business Graphics, and BCS Email framework.

🔍 Features

Price Spike Detection — Flags POs where price increased more than 20% vs previous orders
Unusual Volume Alert — Detects quantity more than 2x the average for that material
High Vendor Dependency — Warns when a single vendor holds more than 60% of PO share
Weekend PO Detection — Flags POs created on Saturday/Sunday
Top 5 Risk Vendors Popup — Button-triggered ALV popup showing riskiest vendors by alert count
Material Price Trend Graph — 3D bar chart via GRAPH_MATRIX_3D on double-click
Direct Navigation — Double-click PO Number to open ME23N directly

🛠️ Tech Stack

ABAP Report — REUSE_ALV_GRID_DISPLAY
Field Catalog — SLIS_T_FIELDCAT_ALV
Top-of-Page Header — REUSE_ALV_COMMENTARY_WRITE
3D Graph — GRAPH_MATRIX_3D
PF Status — Custom toolbar button ZRISK
Tables Used — EKKO, EKPO, LFA1, MAKT, MARA
