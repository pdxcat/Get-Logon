<#
    .Synopsis
    Gets Information about users logged on to the computer.
    
    .Description
    Checks if anyone is logged on to the computer. The only input required is a computer name. 
    It outputs in a table format (User Name, Login Type, Status and Logon Time).

    .Parameter CompName
    The name of the computer you are checking. Takes FQDN or shorthand.

    .Example
    get-logon.ps1 smiley
    This will output everyone that is logged on to the computer name.
#>

param([string]$CompName)

## This retrieves who is logged on to a computer both locally and remotely. 
## Uses qwinsta to retrieve the information and then converts the information into a object. 
## inputs: none
## outputs: list of users (object)
function get-users{
    ## Retrieves the user information and converts it into a csv format.
    $list = (qwinsta /server:$CompName | foreach { (($_.trim() -replace "\s+",","))} | ConvertFrom-Csv)
    $newlist = @()
    
    ## If users are remotely logged in and disconnected the data is mis-matched formatted.
    ## This fixes the mis-matched data.
    foreach($user in $list){
        if($user.username -notmatch "[a-z]" ){
            $user.state = $user.id
            $user.id = $user.username
            $user.username = $user.sessionname
            $user.sessionname = "remote"
            
            $newlist += $user
        }else{
            $newlist += $user 
        }
    }

    ## Removes non-human users.
    $newlist = $newlist | where {$_.username -ne "rdp-tcp"}
    $newlist = $newlist | where {$_.username -ne "services"}
    $newlist = $newlist | where {($_.username -ne "console")}
    
    return $newlist
}

## This retrieves what time the user logged on to the computer. It only checks for local logins. 
## Input: username (string)
## Outputs: data and (single string)
function get-logontime{ 
    
    param($UserName)

    ## This retrieves the list of logon sessions. 
    $SessionList = (GWMI Win32_LogonSession -ComputerName $CompName) | where {$_.logontype -eq "2"}
    
    ## This retrieves the user information used to match the ID. 
    $UserList = (GWMI Win32_loggedonuser -ComputerName $CompName)
    
    ## Used to store logonID that match  
    $Idlist =@()
    
    ## Matches the username and retrieves the logonID.
    foreach($user in $UserList){
        [string]$UserName = $user.antecedent
        if($UserName.Contains($UserName)){
            [string]$UserId = $user.dependent
            $UserId =$UserId.Substring(42)
            $UserId = $UserId.Replace("""","")
            $Idlist += $UserId
        }
    }
    
    $time=$null
    ## Matches the logonID and retrieves the date and formats the date.
    foreach($LogonId in $Idlist){
        foreach($session in $SessionList){
            if($session.logonid -eq $LogonId ){
                $time=[management.managementdatetimeconverter]::todatetime($session.starttime)
            }
        }
    }

    return $time
}

## This determines wheather a workstation is locked or not locked. It does this by checking if the 
## logonui process running. If the process is running it returns locks. 
## Input: user name
## Output: status of the workstation.
function check-locked{
    param($user)
    try{
        if ((Get-Process logonui -ComputerName $CompName -ErrorAction Stop) -and ($user)) { 
             return "locked"
        } 
    }catch{
        return "not locked"
    }
}

## This manages the creation of the list of users logged on. Also adds information: logon time, 
## status. 
## Input: none
## Output: list of users (object)
function create-list{

    ## This creates the list of users that are logged on to a computer. 
    $list = get-users
    
    ## This is used to add time and status to each user object. 
    foreach($user in $list){
        if($user.sessionname -eq "console"){
            $user.sessionname = "Local Log-in"
            $time = get-logontime($user.username)
            $locked = check-locked($user.username)
            $user | Add-Member -type NoteProperty -Name LogonTime -Value $time
            $user | Add-Member -type NoteProperty -Name Status -Value $locked
        }else{
            $user.sessionname = "Remote Log-in"
            $user | Add-Member -type NoteProperty -Name Status -Value $user.state
        }
    }
    return $list
}

## Used to format the output to make it more readable. 
## Inputs: List of users (object)
## Outputs: Outputs the list of users to the console. 
function format-output{
    param(
        $list
    )
    ## Stores the formatting for each table heading. 
    $LogOnFormat = @{Expression={$_.SessionName};Label="Log-in Type";width=15}
    $UserNameFormat = @{Expression={$_.USERNAME};Label="User Name";width=15}
    $StatusFormat = @{Expression={$_.Status};Label="Status";width=15}

    ## This sorts the list by username and then formats the headings. 
    $list | Sort-Object USERNAME | Format-Table $UserNameFormat,$LogOnFormat,$StatusFormat,LogonTime 
}

## This used to test if the computer is pingable. 
$test = Test-Connection -ComputerName $CompName -count 1 -Quiet


## If the computer pings then it create and outputs the list. 
if($test){
    $userlist = create-list
    format-output($userlist)
}else{
    write-host -ForegroundColor Red "$compname is down"
}
