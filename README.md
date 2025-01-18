# SQL Server to CSV Exporter PowerShell Script

This PowerShell script efficiently exports data from multiple SQL Server tables to CSV files. It utilizes connection pooling, optimized queries, and batch processing to handle large datasets.

Features:

- Multiple Table Support: Exports data from a list of specified tables.
- Connection Pooling: Reuses database connections for improved performance.
- Batch Processing: Exports data in batches to handle large tables efficiently.
- Primary Key Ordering: Orders data by the primary key of each table.
- Customizable Output: Optionally specify a single output file or separate files for each table.
- Error Handling: Includes basic error handling and logging.

Usage:

- Configure Parameters: Modify the script parameters to specify the server, database, table list, and output file options.
- Run the Script: Execute the script with the desired parameters.

Example Usage:
```PowerShell
.\SQL2CSV.ps1 -Server "your_server" -Database "your_database" -TableList "Table1,Table2,Table3" -OutputDirectory "c:/sql2csv_export/"
```
