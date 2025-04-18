Function Start-LogRoll { 
    <#
    .DESCRIPTION
    Rolls the logs incrememnting the number by 1 and deleting any older logs over the allowed maximum count of log files

    .PARAMETER LogName
    Base name of the base log file without an extension

    .PARAMETER LogPath
    Base path to the directory of the base log file

    .PARAMETER LogFiles
    Object containing the result of Get-ChildItem to the path where the rotating logs are stored. Using regex to get only the rotated logs.

    .EXAMPLE
    Confirm-LogRotation -LogFile "C:\Scripts\AU-Test\Test.log"
    Confirm-LogRotation -LogFile "C:\Scripts\AU-Test\Test.log" -LogRotateOpt "7"
    Confirm-LogRotation -LogFile "C:\Scripts\AU-Test\Test.log" -LogRotateOpt "10M"
    Confirm-LogRotation -LogFile "C:\Scripts\AU-Test\Test.log" -LogRotateOpt "10M" -LogZip $False
    #>

    param(
        [string] $LogName, 
        [string] $LogPath,
        [object] $LogFiles,
        [int] $LogCountMax = 5
    ) 

    # Get the working log path from the $LogFiles object that was passed to the function. This may be a temp folder for zip archived logs.
    $WorkingLogPath = $LogFiles[0].Directory

    # Rotate multiple log files if 1 or more already exists
    If ($LogFiles.Count -gt 0) {
        # Iterate over the log files starting at the highest number and decrement down to 1
        For ($i = $LogFiles.Count; $i -ge 0; $i--) {
            # Get rotating log file that we are working on
            $OperatingFile = $LogFiles | Where-Object {$_.Name -eq "$LogName.$i.log"}
            
            # Check it we are over the maximum allowed rotating log files
            If ($i -ge $LogCountMax) {
                # Remove rotating logs that are over the maximum allowed
                Remove-Item "$WorkingLogPath\$($OperatingFile.FullName)" -Force -ErrorAction Stop
            # If we have iterated down to zero, we are working with the base log file
            } ElseIf ($i -eq 0) {
                # Set the rotating log number
                $OperatingNumber = 1
                # Set the name of the new rotated log name
                $NewFileName = "$LogName.$OperatingNumber.log" 
                # Rotate the base log
                Rename-Item -Path "$WorkingLogPath\$LogName.log" -NewName $NewFileName 
                # Return true since all logs have been rotated has been rotated
                Return $True
            # We are iterating through the rotated logs and renaming them as needed
            } Else { 
                # Set the operating number to be +1 of the current increment
                $OperatingNumber = $i + 1
                # Set the name of the new rotated log name
                $NewFileName = "$LogName.$OperatingNumber.log" 
                # Rotate the base log
                Rename-Item -Path "$WorkingLogPath\$LogName.$i.log" -NewName $NewFileName -Force
            } 
        } 
    # Rotate the base log file into its first rotating log file
    } Else {
        Move-Item -Path "$LogPath\$LogName" -Destination "$WorkingLogPath\$LogName.1.log"
        # Return true since base log has been rotated
        Return $True
    }

    # Return false since we didnt rotate any logs
    Return $False
} 

Function Confirm-LogRotation {
    <#
    .DESCRIPTION
    Determines if the log needs to be rotated per the parameters values. It supports rotating log files on disk and stored in a zip archive.

    .PARAMETER LogFile
    The path to the logfile to be rotated

    .PARAMETER LogRotateOpt
    Size of the log file with unit indicator letter or integer of the number of days to rotate the log file (e.g. 10M = 10 Megabytes or 7 = 7 days)

    .PARAMETER LogZip
    Keeping rotated logs inside of a compressed zip archive

    .EXAMPLE
    Confirm-LogRotation -LogFile "C:\Scripts\AU-Test\Test.log"
    Confirm-LogRotation -LogFile "C:\Scripts\AU-Test\Test.log" -LogRotateOpt "7"
    Confirm-LogRotation -LogFile "C:\Scripts\AU-Test\Test.log" -LogRotateOpt "10M"
    Confirm-LogRotation -LogFile "C:\Scripts\AU-Test\Test.log" -LogRotateOpt "10M" -LogZip $False
    #>

    Param(
        [alias ('LF', 'File')][Parameter(Mandatory=$True)][String] $LogFile,
        [alias ('RotateOpt')][string] $LogRotateOpt = "1M",
        [alias('Zip')][bool] $LogZip = $True
    )

    # Initialize default return variable. If returned $True, will write a log rotate line to a new log file.
    $LogRolled = $False

    # Get the log name without the file extension
    $LogName = "$([System.IO.Path]::GetFileNameWithoutExtension($LogFile))"

    # Get the base path to the log file
    $LogPath = Split-Path -Path $LogFile

    # Initialize the zip archive path
    $ZipPath = "$LogPath\$LogName-archive.zip"

    # Initialize the TempLogPath variable to null.
    $TempLogPath = $Null

    # If the zip already exists, we set TempLogPath to a generated user temp folder path
    # This will be used to extract the zip archive before rotating logs
    If (Test-Path $ZipPath) {
        $TempLogPath = [System.IO.Path]::GetTempPath()
    # Else we can read the log files directly off the disk
    } Else {
        # Get the rotating log files only. These have a digit in the filename.
        $LogFiles = Get-ChildItem -Path $LogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
    }

    # Check If existing rotated logs were found
    If ($LogRotateOpt -match '(\d+)([GMK])') {
        $Unit = $matches[2]

        # Calculate the log size and compare it to the LogRotateOpt size
        switch ($Unit) {
            # Gigabytes
            'G' { 
                $RotateSize = [int]$matches[1] * 1GB 
                $LogSize = ((Get-Item -Path "$PSScriptRoot\Logs\$LogName.log").Length) / 1GB
            }
            # Megabytes
            'M' { 
                $RotateSize = [int]$matches[1]* 1MB 
                $LogSize = ((Get-Item -Path "$PSScriptRoot\Logs\$LogName.log").Length) / 1MB
            }
            # Kilobytes
            'K' { 
                $RotateSize = [int]$matches[1] * 1KB 
                $LogSize = ((Get-Item -Path "$PSScriptRoot\Logs\$LogName.log").Length) / 1KB
            }
        }

        If (If $LogSize -gt $RotateSize) {
            If ($LogZip) {
                # Zip archive does not exist yet. Rotate existing logs and put them all insize of a zip archive
                If (!(Test-Path $ZipPath)) {
                    # Get the list of current log files
                    $LogFiles = Get-ChildItem -Path $LogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
                    # Roll the log files
                    $LogRolled = Start-LogRoll -LogName $LogName -LogPath $LogPath -LogFiles $LogFiles
                    # Update the list of current log files after rotating
                    $LogFiles = Get-ChildItem -Path $LogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
                    # Iterate over each log file and compress it into the archive and then delete it off the disk
                    ForEach ($File in $LogFiles) {
                        Compress-Archive -Path "$LogPath\$($File.Name)" -DestinationPath $ZipPath -Update
                        Remove-Item -Path "$LogPath\$($File.Name)"
                    }
                    Return $True
                # Zip archive already exists. Lets extract and rotate some logs
                } Else {
                    # Ensure the temp folder exists
                    If (-Not (Test-Path -Path $TempLogPath)) {
                        New-Item -Path $TempLogPath -ItemType Directory
                    }

                    # Unzip the File to the temp folder
                    Expand-Archive -Path $ZipPath -DestinationPath $TempLogPath -Force

                    # Get the LogFiles from the temp folder
                    $LogFiles = Get-ChildItem -Path $TempLogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
                    
                    # Roll the log files
                    $LogRolled = Start-LogRoll -LogName $LogName -LogPath $LogPath -LogFiles $LogFiles

                    # Compress and overwrite the old log files inside the existing archive
                    Compress-Archive -Path "$TempLogPath\*" -DestinationPath $ZipPath -Update -Force

                    # Remove the Files we extracted, we no longer need them
                    If (Test-Path $TempLogPath) {
                        Remove-Item -Path $TempLogPath -Recurse -Force
                    }

                    # Return True or False
                    Return $LogRolled
                }
            # Logs are not zipped, just roll em over
            } Else {
                $LogFiles = Get-ChildItem -Path $LogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
                $LogRolled = Start-LogRoll -LogName $LogName -LogPath $LogPath -LogFiles $LogFiles
                Return $LogRolled
            }
        }
    } ElseIf ($LogRotateOpt -match '^\d+$') {
        # Convert the string digit into an integer
        $RotateDays = [int]$LogRotateOpt

        # Get the file's last write time
        $CreationTime = (Get-Item $LogPath).CreationTime

        #Calculate the age of the file in days
        $Age = ((Get-Date) - $CreationTime).Days

        # If the age of the file is older than the configured number of days to rotate the log
        If ($Age -gt $RotateDays) {
            If ($LogZip) {
                # Zip archive does not exist yet. Rotate existing logs and put them all insize of a zip archive
                If (!(Test-Path $ZipPath)) {
                    # Get the list of current log files
                    $LogFiles = Get-ChildItem -Path $LogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
                    # Roll the log files
                    $LogRolled = Start-LogRoll -LogName $LogName -LogPath $LogPath -LogFiles $LogFiles
                    # Update the list of current log files after rotating
                    $LogFiles = Get-ChildItem -Path $LogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
                    # Iterate over each log file and compress it into the archive and then delete it off the disk
                    ForEach ($File in $LogFiles) {
                        Compress-Archive -Path "$LogPath\$($File.Name)" -DestinationPath $ZipPath -Update
                        Remove-Item -Path "$LogPath\$($File.Name)"
                    }
                    Return $True
                # Zip archive already exists. Lets extract and rotate some logs
                } Else {
                    # Ensure the temp folder exists
                    If (-Not (Test-Path -Path $TempLogPath)) {
                        New-Item -Path $TempLogPath -ItemType Directory
                    }

                    # Unzip the File to the temp folder
                    Expand-Archive -Path $ZipPath -DestinationPath $TempLogPath -Force

                    # Get the LogFiles from the temp folder
                    $LogFiles = Get-ChildItem -Path $TempLogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
                    
                    # Roll the log files
                    $LogRolled = Start-LogRoll -LogName $LogName -LogPath $LogPath -LogFiles $LogFiles

                    # Compress and overwrite the old log files inside the existing archive
                    Compress-Archive -Path "$TempLogPath\*" -DestinationPath $ZipPath -Update -Force

                    # Remove the Files we extracted, we no longer need them
                    If (Test-Path $TempLogPath) {
                        Remove-Item -Path $TempLogPath -Recurse -Force
                    }

                    # Return True or False
                    Return $LogRolled
                }
            # No zip archiving. Just roll us some logs on the disk.
            } Else {
                $LogFiles = Get-ChildItem -Path $LogPath -File -Filter "*.log" | Where-Object { ($_.Name -like "$LogName*") -and ($_.Name -match '\.\d+')}  | Sort-Object BaseName
                $LogRolled = Start-LogRoll -LogName $LogName -LogPath $LogPath -LogFiles $LogFiles
                Return $LogRolled
            }
        }
    }
}

Function Write-Log {
    <#
    .DESCRIPTION
    Writes output to a log File and optionally to the console with multiple retries and configurable options

    .PARAMETER LogMsg
    Message to be written to the log

    .PARAMETER LogLevel
    Name of a label to indicate the severity of the log

    .PARAMETER LogName
    Name of the log File that will be written to. It will have .log automatically appended as the File extension.

    .PARAMETER LogPath
    Path to the log File. Defaults to a Logs subfolder wherever the script is ran from.

    .PARAMETER DateTimeFormat
    Format of the timestamp to be displayed in the log File or in optional console output

    .PARAMETER NoLogInfo
    Disable logging time and level in the log File or in optional console output

    .PARAMETER Encoding
    Text encoding to write to the log File with

    .PARAMETER LogRetry
    Number of times to retry writing to the log File. Will wait half a second before trying again. Defaults to 2.

    .PARAMETER WriteConsole
    Switch to write the output to the console

    .PARAMETER ConsoleOnly
    Switch to write the output to the console only without logging to the log file

    .PARAMETER ConsoleInfo
    Switch to write the timestamp and log level during WriteConsole

    .EXAMPLE
    Write-Log "This will write a INFO level message to the default log called debug.log"
    Write-Log "This will write a WARNING level message to the default log called debug.log" -LogLevel "WARNING"
    Write-Log "This will write a WARNING level message to a log called Test.log" -LogLevel "WARNING" -LogName "Test"
    Write-Log "This will write a WARNING level message to a log called Test.log with a custom timestamp" -LogLevel "WARNING" -LogName "Test" -DateTimeFormat "yy-mm-dd HH:mm:ss"
    Write-Log "This will write to the log and exclude the timestamp and log level" -NoLogInfo
    Write-Log "This will write a INFO level message to the default log with a specific text encoding" -Encoding "unicode"
    Write-Log "This will write a INFO level message to the default log and retry 5 times if it fails" -LogRetry 5
    Write-Log "This will write a INFO level message to the default log and to the console window" -WriteConsole
    Write-Log "This will write a message to the console only without a timestamp or log level info" -WriteConsole -ConsoleOnly
    Write-Log "This will write a INFO level message to the default log and to the console window with the timestamp and log level shown in the console" -WriteConsole -ConsoleInfo
    Write-Log "This will write a INFO level message to the console only with the timestamp and log level shown" -WriteConsole -ConsoleOnly -ConsoleInfo
    #>

    Param(
        [alias ('LM', 'Msg')][Parameter(Mandatory=$True)][String] $LogMsg,
        [alias ('LL', 'LogLvl')][string] $LogLevel = "INFO",
        [alias ('LN')][string] $LogName = "Debug",
        [alias ('LP')][string] $LogPath ="$PSScriptRoot\Logs",
        [Alias('TF', 'DF', 'DateFormat', 'TimeFormat')][string] $DateTimeFormat = 'yyyy-MM-dd HH:mm:ss',
        [alias ('NLI')][switch] $NoLogInfo,
        [ValidateSet('unknown', 'string', 'unicode', 'bigendianunicode', 'utf8', 'utf7', 'utf32', 'ascii', 'default', 'oem')][string]$Encoding = 'Unicode',
        [alias ('LR', 'Retry')][int] $LogRetry = 2,
        [alias('WC', 'Console')][switch] $WriteConsole,
        [alias('CO')][switch] $ConsoleOnly,
        [alias('CI')][switch] $ConsoleInfo
    )

    # If the Log directory doesnt exist, create it
    If (!(Test-Path -Path $LogPath)) {
        New-Item -ItemType "Directory" -Path $LogPath > $Null
    }

    # If the log file doesnt exist, create it
    If (!(Test-Path -Path "$LogPath\$LogName.log")) {
        Write-Output "[$([datetime]::Now.ToString($DateTimeFormat))][$LogLevel] Logging started" | Out-File -FilePath "$LogPath\$LogName.log" -Append -Encoding $Encoding
    # Else check if the log needs to be rotated. If rotated, create a new log file.
    } ElseIf ((Confirm-LogRotation -LogFile "$LogPath\$LogName.log") -eq $True) {
        Write-Output "[$([datetime]::Now.ToString($DateTimeFormat))][$LogLevel] Log rotated... Logging started" | Out-File -FilePath "$LogPath\$LogName.log" -Append -Encoding $Encoding
    }

    # Write to the console
    If ($WriteConsole) {
        # Write timestamp and log level to the console
        If ($ConsoleInfo) {
            Write-Output "[$([datetime]::Now.ToString($DateTimeFormat))][$LogLevel] $LogMsg"
        # Write just the log message to the console
        } Else {
            Write-Output "$LogMsg"
        }

        # Write to the console only and return to stop the function from writing to the log
        If ($ConsoleOnly) {
            Return
        }
    }

    # Initialize variables for retrying if writing to log fails
    $Saved = $false
    $Retry = 0
    # Retry writing to the log until we have success or have hit the maximum number of retries
    Do {
        # Increment retry by 1
        $Retry++
        # Try to write to the log file
        Try {
            # Write to the log without log info (timestamp and log level)
            If ($NoLogInfo) {
                Write-Output "$LogMsg" | Out-File -FilePath "$LogPath\$LogName.log" -Append -Encoding $Encoding -ErrorAction Stop
            # Write to the log with log info (timestamp and log level)
            } Else {
                Write-Output "[$([datetime]::Now.ToString($DateTimeFormat))][$LogLevel] $LogMsg" | Out-File -FilePath "$LogPath\$LogName.log" -Append -Encoding $Encoding -ErrorAction Stop
            }
            # Set saved variable to true. We successfully wrote to the log file.
            $Saved = $true
        }
        # Catch any errors trying to write to the log file
        Catch {
            If ($Saved -eq $false -and $Retry -eq $LogRetry) {
                # Write the final error to the console. We were not able to write to the log file.
                Write-Error "Write-Log couldn't write to the log File $($_.Exception.Message). Tried ($Retry/$LogRetry))"
                Write-Error "Err Line: $($_.InvocationInfo.ScriptLineNumber) Err Name: $($_.Exception.GetType().FullName)  Err Msg: $($_.Exception.Message)"
            }
            Else {
                # Write warning to the console and try again until we hit the maximum configured number of retries
                Write-Warning "Write-Log couldn't write to the log File $($_.Exception.Message). Retrying... ($Retry/$LogRetry)"
                # Sleep for half a second
                Start-Sleep -Milliseconds 500
            }
        }
    } Until ($Saved -eq $true -or $Retry -ge $LogRetry)
}