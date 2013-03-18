
param($SqlServer = '10.213.252.54',$SqlCatalog = 'Tfs_rnotfsat',$bt = 'rel>rtm>9.2%',$DestinationHome = 'D:\Build\9.2\main\')

function NewestSuccessfulBuild ($nsf_SqlServer,$nsf_SqlCatalog,$nsf_bt)
{
    $SqlQuery = "select  top 1 * 
                from tbl_build as builds with (nolock) 
                left join tbl_buildQuality 
                on builds.QualityId = tbl_buildQuality.qualityid 
                where BuildNumber like '$bt'  and BuildStatus = 2   and builds.Deleted = 0  
                and (tbl_BuildQuality.quality like 'Release%' or tbl_BuildQuality.quality = 'BVT In Progress')            
                order by StartTime desc"
                
                
    $ConnectionString = "Server = $nsf_SqlServer; Database = $nsf_SqlCatalog; Integrated Security = True"
    #$ConnectionString = "Server = rnotfsdt; Database = Tfs_rnotfsat; Integrated Security = True"
    $Connection = new-object "System.Data.SqlClient.SqlConnection"  $ConnectionString
    $Connection.Open()
    $DataAdapter = New-Object "System.Data.SqlClient.SqlDataAdapter" ($SqlQuery,$Connection)
    $DataSet = new-object "System.Data.DataSet"
    $DataAdapter.Fill($DataSet, "TempTableInDataSet") | out-null
    $Connection.Close()
    $Table = $DataSet.Tables["TempTableInDataSet"]
    $buildNum = $Table.Rows[0].item(2) 
    $buildNum = $buildNum.replace(">","_")
    $buildNum = $buildNum.replace('"',"-")
    $buildNum = $buildNum.replace('\',"")
    $dropLocation = $Table.Rows[0].item(8)
    $rtn = @{"BuildNumber" = $buildNum; "DropLocation" = $dropLocation}
    return($rtn)
}
Write-Host "Starting Script Copy Dev Build"
Write-Output "$(Get-Date -f G) Starting Script Copy Dev Build" 
$LoopVariable = 1
$LoopRuns = 0
$CopiedBuildNumber = 0
if ($SQLServer -and $SQLCatalog -and $bt -and $DestinationHome)
{
    While($LoopVariable = 1)
    {
        Write-Host "Script has run $LoopRuns times"
        Write-Output "$(Get-Date -f G) Script has run $LoopRuns times" 
        
        # To monitor disk space usage
        $volumeSet = Get-WmiObject -Class win32_volume -ComputerName localhost -filter "drivetype = 3"
        foreach($volume in $volumeSet)
        {
            $drive = $volume.DriveLetter
           if ($drive -eq "d:")
            {
                [int]$free = $volume.FreeSpace/1GB
                [int]$capacity = $volume.Capacity/1GB
                Write-Host -ForegroundColor blue "Free space on $drive = $free 't't Total Capacity on $drive = $capacity"
                if ($free -lt 5)
                {
                    Write-Host -ForegroundColor red "Remove the top 5 old build folder to release space."
                    $LocalBuildFolder01 = $DestinationHome
                    Get-ChildItem $LocalBuildFolder01 | Sort-Object |select-Object -first 5 | Remove-Item -Recurse -Force
            
                }
            }
        }
        
        $NewestBuild = NewestSuccessfulBuild $SqlServer $SqlCatalog $bt
        $BuildNumber = $NewestBuild.BuildNumber
        while($BuildNumber -eq $CopiedBuildNumber)
        {
            Write-Host "Build $BuildNumber already copied, waiting 1 hours"
            sleep -Seconds 3600
            $NewestBuild = NewestSuccessfulBuild $SqlServer $SqlCatalog $bt
            $BuildNumber = $NewestBuild.BuildNumber
        }
        Write-Host "New build" $BuildNumber "found"
        $BuildDrop = $NewestBuild.DropLocation
        $BuildSubDir = $BuildDrop + "\PaPush\"
        $BuildDestination = $DestinationHome + $BuildNumber
        $FileList = get-childitem $BuildSubDir * -Recurse -Include *.* -Exclude *.zip
        # create path if necessary
        if ((Test-Path -path $BuildDestination) -ne $True) 
        {
            New-Item $BuildDestination -type Directory
        }
        if (Test-Path -path $BuildSubDir) 
        {
            foreach ($File in $FileList) 
            {
                $subfolder = $File.fullname.replace($BuildSubDir,"")
                $subfolderArrayList = New-Object System.Collections.ArrayList
                foreach ($sub in $subfolder.Split("\")) 
                {
                    $subfolderArrayList.Add($sub)
          	}
        		if (($subfolderArrayList[0] -eq "MDMG") -or ($subfolderArrayList[0] -eq "Drop Utility") -or ($subfolderArrayList[0] -eq "Attendant Workstation") -or ($subfolderArrayList[0] -eq "Advantage Scan")) 
                {
        		  #leave folder structure intact
        		}
        		elseif ($subfolderArrayList[0] -eq "EZpay") 
                {
                    #remove /ezpay/ezpay application directories
                    $subfolderArrayList.remove($subfolderArrayList[0])
                    $subfolderArrayList.remove($subfolderArrayList[0])
        		}
        		else 
                {
                    #remove leading directory
                    $subfolderArrayList.remove($subfolderArrayList[0])
        		}
        		if ($subfolderArrayList[0] -match "_") 
                {
        			#take the underscore character out of the first folder, this is for ADV_Install_Tools
        			$subfolderArrayList[0] = $subfolderArrayList[0] -Replace "_", ""
        		}
        		$newsubfolder = ""
        		foreach ($item in $subfolderArrayList) 
                {
        			$newsubfolder += "\" + $item
        		}
        		$newsubfolder = $newsubfolder.Replace($File.name,"")
        		$BuildDestinationSub = $BuildDestination + $NewSubfolder
        		if (Test-Path $BuildDestinationSub) 
                {
        			Write-Output "$(Get-Date -f G) Copying $File"
        			copy-item $File -Destination $BuildDestinationSub
                    #& Robocopy.exe $File $BuildDestinationSub /S /E /MT:250
        			Write-Output "$(Get-Date -f G) $File copied to $BuildDestinationSub"
        		}
        		else 
                {
                    New-Item $BuildDestinationSub -Type Directory 
                    Write-Output "$(Get-Date -f G) Copying $File"
        			copy-item $File $BuildDestinationSub 
                    #& Robocopy.exe $File $BuildDestinationSub /S /E /MT:250
        			Write-Output "$(Get-Date -f G) $File copied to $BuildDestinationSub"
        		}
        				
        	}
        	#create success file
        	Write-Host "Build: $BuildNumber Successful! "
        	Write-Output "$(Get-Date -f G) Build: $BuildNumber Successful!" 
        	New-Item "$BuildDestination\success.txt" -Type File
        	"Build $BuildNumber Successful!" >> "$BuildDestination\success.txt"
            $CopiedBuildNumber = $BuildNumber
<##  copy build to bonus folder.         
            #Copy Build to Bonus Team build folder
            $bonusDst = "\\10.222.116.66\autoinstall\build\"

            Get-ChildItem $bonusDst | Remove-Item  -Recurse -Force

            $StartTime = Get-Date
            Write-Host "Robocopy Start time is $StartTime!"
            & Robocopy.exe $BuildDestination $bonusDst /S /E /MT:150
            $EndTime = Get-Date
            Write-Host "Robocopy End time is $EndTime ...."
##>            
        }
        Write-Output "$(Get-Date -f G) Copy complete, Sleeping 1 hours." 
        Write-Host "$(Get-Date -f G) Copy complete, Sleeping 1 hours." 
        # sleep 4 hours this build is done.
        sleep -s 14400
        $LoopRuns++	
    }
}
else
{
    if(-not $SqlServer){Write-Host "Missing SQL server value, try ""rnotfsdt"""}
    if(-not $SqlCatalog){Write-Host "Missing SQL server catalog value, try ""tfsbuild"""}
    if(-not $bt){Write-Host "Missing build type value, try ""dev>adv>9.1%"",""rel>rtm>9.0%"", or ""main>9.1%"""}
    if(-not $DestinationHome){Write-Host "Missing destination value"}
}
