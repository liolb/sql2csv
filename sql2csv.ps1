# Example usages: 
# .\SQL2CSV.ps1 -Server "your_server" -Database "your_database" -TableList "Table1,Table2,Table3" -OutputDirectory "C:\Temp"


# accept parameters for the server, database, tables and output directory 
param(
    [Parameter(Mandatory=$true)]
    [string]$Server,

    [Parameter(Mandatory=$true)]
    [string]$Database,

    [Parameter(Mandatory = $true)]
    [string]$TableList,

    [Parameter(Mandatory=$true)]
    [string]$OutputDirectory
)

# Function to write log messages to the console and a log file
function Write-Log {
  param (
      [string]$Message
  )
  Write-Host $Message
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  "$timestamp   $Message" | Out-File -FilePath ".\script_output.log" -Append
}

# Function to clear the log file
function Clear-Log {
  # check if log file exists and delete it 
  if (Test-Path ".\script_output.log") {
    Remove-Item ".\script_output.log"
  }
  # create a new log file
  New-Item -ItemType File -Path ".\script_output.log"
}

# Function to get the total row count from the table
function Get-TableRowCount {
  param(
    [string]$Server,
    [string]$Database,
    [string]$Table
  )
  # Open a connection to the database
  $Connection = New-Object System.Data.SqlClient.SqlConnection
  # Use trusted connection to avoid storing credentials in the script
  # Pooling is enabled to improve performance
  $Connection.ConnectionString = "server=$Server;database=$Database;trusted_connection=true;Pooling=true;"
  try {
    $Connection.Open()
    $Command = New-Object System.Data.SqlClient.SqlCommand
    $Command.Connection = $Connection
    $Command.CommandText = "SELECT COUNT(*) FROM $Table"
    [int]$rowCount = $Command.ExecuteScalar()
    return $rowCount
  }
  finally {
    if ($Connection.State -eq 'Open') { $Connection.Close() }
  }
}

# Function to get the names of primary key columns from the table
function Get-PrimaryKeyColumns {
  param(
    [string]$Server,
    [string]$Database,
    [string]$Table
  )

  # Open a connection to the database
  $Connection = New-Object System.Data.SqlClient.SqlConnection
  # Use trusted connection to avoid storing credentials in the script
  # Pooling is enabled to improve performance
  $Connection.ConnectionString = "server=$Server;database=$Database;trusted_connection=true;Pooling=true;"
  try {
    $Connection.Open()
    $Command = New-Object System.Data.SqlClient.SqlCommand
    $Command.Connection = $Connection
    # Query to get the primary key column name
    # This query assumes that the table has only one primary key column
    # If the table has multiple primary key columns, you may need to modify the query
    # to handle that case
    # The query uses INFORMATION_SCHEMA views to get the primary key column name
    # The query filters the results based on the table name
    # The query returns the column name of the primary key column
    # If the table does not have a primary key, the query will return null 
    $Command.CommandText = @"
SELECT Col.Column_Name 
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS Tab
INNER JOIN INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE Col 
    ON Col.Constraint_Name = Tab.Constraint_Name
    AND Col.Table_Name = Tab.Table_Name
WHERE Constraint_Type = 'PRIMARY KEY'
AND Col.Table_Name = '$Table'
"@

    # Execute the query; this delivers a table with the primary key column names
    # as rows (field index 0); iterate over the rows and concatenate the column names
    $reader = $command.ExecuteReader() 
    $rows = @()
    while ($reader.Read()) {$rows += $reader.GetValue(0)}
  
    $primaryKeyColumnNameCSV = $rows -join ", "
    return $primaryKeyColumnNameCSV   
  }
  finally {
    if ($Connection.State -eq 'Open') { $Connection.Close() }
  }
}

# Clear the log file
Clear-Log

# Batch settings
[int]$BatchSize = 100000

Write-Log "SQL2CSV Powershell script executing..."
Write-Log "* Source-Server        : $Server"
Write-Log "* Source-Database      : $Database"
Write-Log "* Output-Directory     : $OutputDirectory"
Write-Log "* SQL2CSV-BatchSize    : $BatchSize"

# Check if the output directory exists
if (-not (Test-Path $OutputDirectory)) {
    Write-Log "Output directory does not exist. Creating it..."
    New-Item -ItemType Directory -Path $OutputDirectory
}

$Tables = $TableList -split ","
foreach ($Table in $Tables) {
  # Remove leading and trailing spaces from the table name
  $Table = $Table.Trim()

  # Initialize the starting row
  [int]$StartRow = 1

  # Construct the output file path
  $filename = "$Table.csv"
  $OutputCSVFile = Join-Path -Path $OutputDirectory -ChildPath $filename

  # Delete existing output file if it exists
  if (Test-Path $OutputCSVFile) { Remove-Item $OutputCSVFile -Force }

  # Get total row count
  $rowCount = Get-TableRowCount -Server $Server -Database $Database -Table $Table

  # Get name of primary key
  $primaryKeyColumns = Get-PrimaryKeyColumns -Server $Server -Database $Database -Table $Table

  # Log some information
  Write-Log "Export started for table $Table" 
  Write-Log "* Source-Table Name    : $Table"
  Write-Log "* Primary-Key          : $primaryKeyColumns"
  Write-Log "* Source-RowCount      : $rowCount"  
  Write-Log "* Target-CSV File      : $OutputCSVFile"

  # if row count is 0, create csv flie with header and continue to next table
  if ($rowCount -eq 0) {
    Write-Log "Table $Table has no rows. Creating an empty CSV file."
    $header = (Invoke-Sqlcmd -Query "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$Table'" -Database $Database -Server $Server).COLUMN_NAME
    $header -join "," | Out-File -FilePath $OutputCSVFile -Encoding UTF8
    continue
  }
  
  # If the table does have a primary key; if not continue to the next table
  if (-not $primaryKeyColumns) {
    Write-Log "Table $Table does not have a primary key. Skipping export."
    continue
  }

  # Loop through the table in batches
  while ($StartRow -le $rowCount) {
    $EndRow = [Math]::Min($StartRow + $BatchSize - 1, $rowCount)
    Write-Log "Exporting rows $StartRow to $EndRow"

    # Construct the SQL query with the current batch's range
    $Query = "SELECT * FROM $Table ORDER BY $primaryKeyColumns ASC OFFSET $($StartRow - 1) ROWS FETCH NEXT $BatchSize ROWS ONLY"

    Write-Log "Query: $Query"

    # Execute the query 
    # Append the current batch to the CSV file
    Invoke-Sqlcmd -Query $Query -Database $Database -Server $Server |
    Export-Csv -NoTypeInformation -Path $OutputCSVFile -Encoding UTF8 -Append

    # Increment the starting row for the next batch
    $StartRow += $BatchSize
  }   

  Write-Log "Export completed for table $Table"
}
