
$hcinode = '<hci-server-name>'
$resourceGroup = "<Your Arc Resource Group>"
$location = "<Region of resource>"
$subscriptionId = "<Azure Subscription ID>"
$appId = "<App ID of Service Principal>"
$password = "<Ap ID Secret>"
$tenant = "<Tenant ID for Service Principal>"


$azAccountModule = Get-Module -ListAvailable -Name Az.Accounts
$azResourcesModule = Get-Module -ListAvailable -Name Az.Resources
$azOperationalInsights = Get-Module -ListAvailable -Name Az.OperationalInsights

function Install-AzModules {
    # checks the required Powershell modules exist and if not exists, request the user permission to install.  Function taken from enable-monitoring script


    if (($null -eq $azAccountModule) -or ($null -eq $azResourcesModule) -or ($null -eq $azOperationalInsights)) {

        $isWindowsMachine = $true
        if ($PSVersionTable -and $PSVersionTable.PSEdition -contains "core") {
            if ($PSVersionTable.Platform -notcontains "win") {
                $isWindowsMachine = $false
            }
        }

        if ($isWindowsMachine) {
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

            if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Host("Running script as an admin...")
                Write-Host("")
            }
            else {
                Write-Host("Please re-launch the script with elevated administrator") -ForegroundColor Red
                Stop-Transcript
                exit
            }
        }

        $message = "This script will try to install the latest versions of the following Modules : `
			        Az.Resources, Az.Accounts  and Az.OperationalInsights using the command`
			        `'Install-Module {Insert Module Name} -Repository PSGallery -Force -AllowClobber -ErrorAction Stop -WarningAction Stop'
			        `If you do not have the latest version of these Modules, this troubleshooting script may not run."
        $question = "Do you want to Install the modules and run the script or just run the script?"

        $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes, Install and run'))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Continue without installing the Module'))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Quit'))

        $decision = $Host.UI.PromptForChoice($message, $question, $choices, 0)

        switch ($decision) {
            0 {

                if ($null -eq $azResourcesModule) {
                    try {
                        Write-Host("Installing Az.Resources...")
                        Install-Module Az.Resources -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
                    }
                    catch {
                        Write-Host("Close other powershell logins and try installing the latest modules forAz.Accounts in a new powershell window: eg. 'Install-Module Az.Accounts -Repository PSGallery -Force'") -ForegroundColor Red
                        exit
                    }
                }

                if ($null -eq $azAccountModule) {
                    try {
                        Write-Host("Installing Az.Accounts...")
                        Install-Module Az.Accounts -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
                    }
                    catch {
                        Write-Host("Close other powershell logins and try installing the latest modules forAz.Accounts in a new powershell window: eg. 'Install-Module Az.Accounts -Repository PSGallery -Force'") -ForegroundColor Red
                        exit
                    }
                }

                if ($null -eq $azOperationalInsights) {
                    try {

                        Write-Host("Installing Az.OperationalInsights...")
                        Install-Module Az.OperationalInsights -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
                    }
                    catch {
                        Write-Host("Close other powershell logins and try installing the latest modules for Az.OperationalInsights in a new powershell window: eg. 'Install-Module Az.OperationalInsights -Repository PSGallery -Force'") -ForegroundColor Red
                        exit
                    }
                }

            }
            1 {

                if ($null -eq $azResourcesModule) {
                    try {
                        Import-Module Az.Resources -ErrorAction Stop
                    }
                    catch {
                        Write-Host("Could not import Az.Resources...") -ForegroundColor Red
                        Write-Host("Close other powershell logins and try installing the latest modules for Az.Resources in a new powershell window: eg. 'Install-Module Az.Resources -Repository PSGallery -Force'") -ForegroundColor Red
                        Stop-Transcript
                        exit
                    }
                }
                if ($null -eq $azAccountModule) {
                    try {
                        Import-Module Az.Accounts -ErrorAction Stop
                    }
                    catch {
                        Write-Host("Could not import Az.Accounts...") -ForegroundColor Red
                        Write-Host("Close other powershell logins and try installing the latest modules for Az.Accounts in a new powershell window: eg. 'Install-Module Az.Accounts -Repository PSGallery -Force'") -ForegroundColor Red
                        Stop-Transcript
                        exit
                    }
                }

                if ($null -eq $azOperationalInsights) {
                    try {
                        Import-Module Az.OperationalInsights -ErrorAction Stop
                    }
                    catch {
                        Write-Host("Could not import Az.OperationalInsights... Please reinstall this Module") -ForegroundColor Red
                        Stop-Transcript
                        exit
                    }
                }

            }
            2 {
                Write-Host("")
                Stop-Transcript
                exit
            }
        }
    }

}


function Install-Choco {

    #requires -RunasAdministrator
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

}


function Install-Helm {

    #requires -RunasAdministrator
    $chocoExist = (Get-Command ".\choco", "choco" -ErrorAction Ignore -CommandType Application) -ne $null

    if (-not $chocoExist) {
        Install-Choco 
    }
    choco install kubernetes-helm -y
}


#MAIN

# Check Az Modules exist on local machine

if (($null -eq $azAccountModule) -or ($null -eq $azResourcesModule) -or ($null -eq $azOperationalInsights)) {
    Install-AzModules
}

# Check if Helm exists on local system

$HelmExist = (Get-Command ".\helm", "helm" -ErrorAction Ignore -CommandType Application) -ne $null

if (-not $HelmExist) {Install-Helm}


$session = New-PSSession -ComputerName $hcinode
#Make sure the AksHCI Module is loaded on the remote system.  Assume it is already present.
invoke-command -Session $session -ScriptBlock {set-executionpolicy Bypass; import-module akshci -Global -Force -PassThru }
# Run this command to get the list of AKS HCI Clusters
Invoke-Command -Session $session -ScriptBlock {get-akshcicluster}
$aksClusters = Invoke-Command -Session $session -ScriptBlock {get-akshcicluster}

$localWssdDir = "c:\wssd"

if (-not (test-path -Path $localWssdDir -PathType Container)) {
    md $localWssdDir | out-null
}

#Copy Kubectl.exe to the local machine
$kubeCtlRemoteFile = "$env:ProgramFiles\akshci\kubectl.exe"
$kubectl = "$localWssdDir\kubectl.exe"
if (-not (test-path -path $kubectl -PathType leaf)){
    copy-item -Path $kubeCtlRemoteFile -Destination $localWssdDir -FromSession $session

}

# Set the KUBECONFIG environment variable
if (-not $Env:KUBECONFIG) {
    $Env:KUBECONFIG="$HOME\.kube\config"
}


#Get the Enable Monitoring Script
$monitorScriptFileName = 'enable-monitoring.ps1'

$monitorScriptFile = "$($localWssdDir)\$($monitorScriptFileName)"
if (-not(test-path -path $monitorScriptFile -PathType Leaf)){
    Invoke-WebRequest https://aka.ms/enable-monitoring-powershell-script -OutFile $monitorScriptFile
}




#Get the AKS Cluster config files for each cluster deployed to HCI
foreach ($aksCluster in $aksClusters) {
    if ($aksCluster.Phase -eq 'provisioned') {
        write-output $aksCluster.Name
        $aksHciCluster = $aksCluster.Name
        $azureArcClusterResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Kubernetes/connectedClusters/$aksHciCluster"

        

        # Run this to get the kube-config file for the cluster you want to manage. Getting the outpuit from the remote command doesn't work, so using the transcript function to 
        # record the location of the file "- kubeconfig will be written to:"
        $output = Start-Transcript
        Invoke-Command -Session $session -ScriptBlock {get-akshcicredential -clustername $using:aksHciCluster}
        Stop-Transcript

        $regex = 'INFO:  - kubeconfig will be written to: *'
        $kubeConfRemoteFile = ((Get-Content $output.path | Where-Object {$_ -like "$regex"}) -split $regex)[1]

        $localConfFile = "c:\wssd\conf-$aksHciCluster"
        # Set the kubeconfig to use the retrieved config

      
        if ($env:KUBECONFIG -notlike "*$localConfFile*") {
            $Env:KUBECONFIG="$Env:KUBECONFIG;$localConfFile"
            write-output ('INFO: {0} added to  {1}.' -f $localConfFile, $Env:KUBECONFIG)
        } 
        else {
            write-output ('INFO: {0} already exists in {1}. Skipping' -f $localConfFile, $Env:KUBECONFIG)
          }

        copy-item -Path $kubeConfRemoteFile -Destination $localConfFile -FromSession $session

        #To make it easy for helm ops, copy the kubeconfig file to the default dir 

        copy-item -path $localConfFile -Destination $env:USERPROFILE\.kube\config

        $kubeContexts = (. $kubectl config get-contexts)
        foreach ($entry in $kubeContexts) {
            $kubeContext = ($entry -replace '\s+', ' ').split(' ')
            If ($kubeContext[2] -eq $aksHciCluster) {
                $kubeContextName = $kubeContext[1]
            }
        }
        #Onboard the cluster to Arc
        try {
            $AzureArcClusterResource = Get-AzResource -ResourceId $azureArcClusterResourceId
            }
        Catch {}
        if ($null -eq $AzureArcClusterResource) { 
            # Just in case someone has deleted the resource in Azure and not cleaned up       
            # Invoke-Command -Session $session -ScriptBlock { Uninstall-AksHciArcOnboarding -clustername $using:aksHciCluster}
            # Deploy the Arc agent to the cluster
            Start-sleep -Seconds 20
            Invoke-Command -Session $session -ScriptBlock { Install-AksHciArcOnboarding -clustername $using:aksHciCluster -location $using:location -tenantId $using:tenant -subscriptionId $using:subscriptionId -resourceGroup $using:resourceGroup -clientId $using:appId -clientSecret $using:password }
            # Wait until the onboarding has completed...
            start-sleep -Seconds 20
            . $kubectl logs job/azure-arc-onboarding -n azure-arc-onboarding --follow
        }

             
        $kubeContext = $kubeContextName
        $logAnalyticsWorkspaceResourceId = ""
        $proxyEndpoint = ""

        $AzureArcClusterResource = Get-AzResource -ResourceId $azureArcClusterResourceId
        if ($AzureArcClusterResource) {
            . $monitorScriptFile -clusterResourceId $azureArcClusterResourceId -kubeContext $kubeContext -workspaceResourceId $logAnalyticsWorkspaceResourceId -proxyEndpoint $proxyEndpoint
        }
        else {
            Write-Host("The cluster has not been onboarded to Azure Arc.  Please rectify $azureArcClusterResourceId ") -ForegroundColor Red
        }

    }
   
}  




