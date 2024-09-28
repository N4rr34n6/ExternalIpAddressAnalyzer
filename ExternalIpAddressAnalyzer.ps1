# ExternalIpAddress.ps1 -xmlOutputDir "LogsXML" -csvPath "IP_Addresses.csv"
param (
    [string]$xmlOutputDir = "XML",
    [string]$csvPath = "IP_Addresses.csv"
)

# Fixed ETL log directory
$logDir = "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Logs"

# Create XML output directory if it doesn't exist
if (-not (Test-Path $xmlOutputDir)) {
    New-Item -Path $xmlOutputDir -ItemType Directory
}

# Get ETL files and convert to XML
$files = Get-ChildItem $logDir -Filter dosvc*.etl -File | Sort-Object Name

foreach ($file in $files) {
    try {
        $xmlOutputPath = Join-Path $xmlOutputDir "$($file.BaseName).xml"
        tracerpt.exe $file.FullName -of xml -o $xmlOutputPath -lr
    } catch {
        Write-Host "Error processing $($file.FullName): $_"
    }
}

# Initialize CSV file with headers if it doesn't exist
if (-not (Test-Path $csvPath)) {
    "Timestamp,IP Address" | Out-File -FilePath $csvPath
}

# Iterate over generated XML files and extract IP addresses
$xmlFiles = Get-ChildItem $xmlOutputDir -Filter *.xml -File

foreach ($xmlFile in $xmlFiles) {
    try {
        # Load the XML content
        [xml]$xmlContent = Get-Content $xmlFile.FullName
        
        # Create an XmlNamespaceManager to handle namespace
        $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xmlContent.NameTable)
        $namespaceManager.AddNamespace('ns', 'http://schemas.microsoft.com/win/2004/08/events/event')

        # Extract <Data> elements with attribute Name="msg"
        $msgElements = $xmlContent.SelectNodes('//ns:Data[@Name="msg"]', $namespaceManager)

        foreach ($element in $msgElements) {
            # Get the content of the 'msg' field
            $msgContent = $element.'#text'

            # Analyze the JSON content in the 'msg' field
            if ($msgContent -match '"ExternalIpAddress":"(?<ip>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})"') {
                $ip = $matches['ip']
                
                # Extract the timestamp of the event
                $timeCreated = $xmlContent.SelectSingleNode('//ns:System/ns:TimeCreated', $namespaceManager)
                $timestamp = [DateTime]::Parse($timeCreated.SystemTime)
                
                "$timestamp,$ip" | Add-Content -Path $csvPath
            }
        }
    } catch {
        Write-Host "Error processing $($xmlFile.FullName): $_"
    }
}

# Read the CSV file
$ipData = Import-Csv -Path $csvPath

# Count the number of times each IP appears
$ipCount = $ipData | Group-Object -Property "IP Address" | Select-Object Name, @{Name="Count"; Expression={ $_.Count }}

# Display the results with headers
Write-Host "Summary of Found IP Addresses"
Write-Host "-------------------------------"
$ipCount | ForEach-Object { Write-Output "$($_.Name) - $($_.Count) times" }

# Remove temporary XML files
Remove-Item -Path $xmlOutputDir -Recurse -Force

Write-Host "`nProcess completed. IP addresses have been exported to $csvPath"
