﻿$Global:BaseUrl = "http://www.reddit.com"
$Global:UserAgent = "User-Agent PoShBot/1.0 Beta by Davotronic5000"
$Global:ApiType = "json"
$Global:PoShBotLogs = $env:USERPROFILE

#region Connect-Reddit

<# 
.SYNOPSIS
Function to connect to reddit and creat a global session, to allow other reddit commands to be authenticated

.DESCRIPTION
Connects to reddit with supplied credentials and authenticates to collect a modhash and session data.

.PARAMETER  Credential
Credentials to connect to reddit, accepts PSCredential object

.PARAMETER Remember
Boolean parameter sets if Session data should be persisitant

.EXAMPLE
Connect-Reddit -Credential "PoShBot" -Remember $True

.INPUTS
None

.OUTPUTS
$GLobal:Session - Reddit Session data
$Global:ModHash - Reddit API modhash
.NOTES
Created By: Dave Garnar/Davotronic5000

.LINK
http://davotronic5000.co.uk/blog
http://reddit.com/r/PowerShell
#>

FUNCTION Connect-Reddit
    {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")] 
    PARAM
        (
        [parameter(Mandatory=$true)]
        [Alias("Username","Cred")]
      	[System.Management.Automation.PSCredential]
      	[System.Management.Automation.Credential()]$Credential =  [System.Management.Automation.PSCredential]::Empty,
        
        [PSDefaultValue(Help = "True")]
        $Remember = $True
        )

    $Params = @{
    "api_type" = $Global:ApiType
    "passwd" = $Credential.GetNetworkCredential().Password
    "rem" = $Remember
    "user" = $Credential.UserName
    }
    IF ($psCmdlet.ShouldProcess($Global:BaseUrl, "Connecting with Username $($Credential.UserName)"))
        {
        TRY
            {
            Write-Verbose "Logging in to Reddit"
            $Login = Invoke-WebRequest -uri "$Global:BaseUrl/api/login" -Method Post -Body $Params -SessionVariable Global:Session -UserAgent $Global:UserAgent | ConvertFrom-Json
            }
        Catch
            {
            Write-Error -RecommendedAction Stop -Message "Unable to connect to Reddit" -Exception $_.Exception.Message
            }

        IF ($Login.json.data.modhash -and $Global:Session.Cookies.count -gt 0)
            {
            Write-Verbose "Successfully logged in to reddit"
            $Global:ModHash = $Login.json.data.modhash
            }
        ELSEIF ($Login.json.errors -like "*WRONG_PASSWORD*")
            {
            Write-Error -RecommendedAction Stop -Message "Incorrect Username or Password, please re-run the command with the correct details"
            }
        ELSEIF ($login.json.errors -like "*RATELIMIT*")
            {
            Write-Error -RecommendedAction Stop -Message "$($login.json.errors)"
            }
        }
    }
#endregion

#region Submit-Post

<# 
.SYNOPSIS
Submits a post to your chosen subereddit

.DESCRIPTION
function to subint a link or self post to yuor chosen subreddit

.PARAMETER  PostType
Whether post is a link or self post

.PARAMETER Resubmit
Whether a link post should be resubmitted if it has been posted previously

.PARAMETER SavePost
Should post be saved to your profile saved list

.PARAMETER SubReddit
Which subreddit the post will be submitted to

.PARAMETER PostBody
The body text if the post is a self post

.PARAMETER PostTitle
The title of the submitted post

.PARAMETER PostLink
If the post is a link post, this specifys the link.

.PARAMETER NumRetry
Number of times a submit attempt will be made on fixable errors

.PARAMETER FailOnCaptcha
Function will not pause for user input on captcha, the post will just fail to submit

.EXAMPLE
Submit-Post -PostType self -SubReddit "PowerShell" -PostBody "Test Message" -PostTitle "Test Post"

.Example
Submit-Post -PostType link -SubReddit "PowerShell" -PostLink "http://www.powershell.org" -ReSubmit $True

.INPUTS


.OUTPUTS


.NOTES
Created By: Dave Garnar/Davotronic5000

.LINK
http://davotronic5000.co.uk/blog
http://reddit.com/r/PowerShell
#>

FUNCTION Submit-Post
    {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")]
    PARAM
        (
        [parameter(Mandatory=$true)]
        [ValidateSet("self", "link")]
        [STRING]$PostType,

        [parameter(ParameterSetName="Link")]
        [PSDefaultValue(Help = 'False')]
        [BOOL]$Resubmit = $False,

        [BOOL]$SavePost,

        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [PSDefaultValue(Help = 'PowerShell')]
        [STRING]$SubReddit = "PowerShell",

        [parameter(Mandatory=$true, ParameterSetName="Self")]
        [ValidateNotNullOrEmpty()]
        [STRING]$PostBody,

        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [STRING]$PostTitle,

        [parameter(Mandatory=$true, ParameterSetName="Link")]
        [ValidateNotNullOrEmpty()]
        [STRING]$PostLink,

        [PSDefaultValue(Help = 'False')]
        [BOOL]$FailOnCaptcha = $False,

        )

#add a default footer to posts made by the bot
    $PostBody = @"
$PostBody
---
This is an automated post submitted by PoShBot a reddit bot written in PowerShell by /u/Davotronic5000.
My Source code is avaialable here: [PoShBot Git](https://github.com/davotronic5000/PoSh_Reddit_Bot)
"@

    $params = @{
    "api_type" = $Global:ApiType
    "kind" = $PostType
    "resubmit" = $Resubmit
    "save" = $SavePost
    "extension" = "json"
    "sr" = $SubReddit
    "text" = $PostBody
    "title" = $PostTitle
    "uh" = $Global:Modhash
    "url" = $PostLink
    }

    IF ($psCmdlet.ShouldProcess("## object ##", "## message ##"))
        {
        #Keep trying to submit post until either there is no error or an unfixable error is found 
        DO
            {
            #reset error variable for each run through
            $Problem = $null 
            TRY
                {
                $Submit = Invoke-WebRequest -uri "$Global:BaseUrl/api/submit" -Method Post -Body $Params -WebSession $GLOBAL:Session -UserAgent $Global:UserAgent | ConvertFrom-Json
                }
            CATCH
                {
                Write-Error -RecommendedAction Stop -Message "Failed to submit the post to Reddit" -Exception $_.Exception.Message
                }
            IF ($Submit.json.errors)
                {
                $Problem = Debug-Errors -input $submit
                }
            #if errror is bad captcha then get captcah answer
            IF ($Problem.Action -eq "TRY_WITH_CAPTCHA")
                {

                IF ($FailOnCaptcha -eq $False)
                    {
                    #Get Captcha answer
                    $Captcha = Resolve-Captcha -CaptchaIden $Submit.json.captcha
                    Write-Verbose "Adding captcha details in to API parameters"
                    $Params += @{
                        "captcha" = $Captcha.Answer
                        "iden" = $Captcha.Iden
                        }
                    }
                }
            }
        Until (-not $Problem -or $Problem.Action -eq "STOP")
        }
    }

#endregion

#region Resolve-Captcha
<# 
.SYNOPSIS
Solves a captcha

.DESCRIPTION
Function to prompt for user input to solve a captcha when required by the API

.PARAMETER  CaptchaIden
ID of the required captcha, accepts pipeine input

.EXAMPLE
Resolve-Captcha -CaptchIden "BRxX7YD9ysKxUnlvWVMYSFoPjZoeacUN"

.INPUTS
None

.OUTPUTS
Outputs object with captcha Iden and Captcha answer

.NOTES
Created By: Dave Garnar/Davotronic5000

.LINK
http://davotronic5000.co.uk/blog
http://reddit.com/r/PowerShell
#>

FUNCTION Resolve-Captcha
    {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")]
    PARAM
        (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [String]$CaptchaIden
        )

    Begin
        {
        #region create captcha form
        #Import Windows formas assemblies
        [reflection.assembly]::loadwithpartialname("System.Windows.Forms") | Out-Null
        [reflection.assembly]::loadwithpartialname("System.Drawing") | Out-Null

        #Generate forms objects
        $frmCaptcha = New-Object System.Windows.Forms.Form
        $btnNewCaptcha = New-Object System.Windows.Forms.Button
        $btnSubmit = New-Object System.Windows.Forms.Button
        $txtCaptcha = New-Object System.Windows.Forms.TextBox
        $imgCaptcha = New-Object System.Windows.Forms.PictureBox
        $InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState

        $System_Drawing_Size = New-Object System.Drawing.Size
        $System_Drawing_Size.Height = 159
        $System_Drawing_Size.Width = 264
        $frmCaptcha.ClientSize = $System_Drawing_Size
        $frmCaptcha.DataBindings.DefaultDataSourceUpdateMode = 0
        $frmCaptcha.Name = "frmCaptcha"
        $frmCaptcha.Text = "Catcha Response"


        $btnNewCaptcha.DataBindings.DefaultDataSourceUpdateMode = 0

        $System_Drawing_Point = New-Object System.Drawing.Point
        $System_Drawing_Point.X = 144
        $System_Drawing_Point.Y = 94
        $btnNewCaptcha.Location = $System_Drawing_Point
        $btnNewCaptcha.Name = "btnNewCaptcha"
        $System_Drawing_Size = New-Object System.Drawing.Size
        $System_Drawing_Size.Height = 50
        $System_Drawing_Size.Width = 108
        $btnNewCaptcha.Size = $System_Drawing_Size
        $btnNewCaptcha.TabIndex = 3
        $btnNewCaptcha.Text = "New Captcha"
        $btnNewCaptcha.UseVisualStyleBackColor = $True
        $btnNewCaptcha.add_Click($btnNewCaptcha_OnClick)

        $frmCaptcha.Controls.Add($btnNewCaptcha)


        $btnSubmit.DataBindings.DefaultDataSourceUpdateMode = 0

        $System_Drawing_Point = New-Object System.Drawing.Point
        $System_Drawing_Point.X = 12
        $System_Drawing_Point.Y = 94
        $btnSubmit.Location = $System_Drawing_Point
        $btnSubmit.Name = "btnSubmit"
        $System_Drawing_Size = New-Object System.Drawing.Size
        $System_Drawing_Size.Height = 50
        $System_Drawing_Size.Width = 109
        $btnSubmit.Size = $System_Drawing_Size
        $btnSubmit.TabIndex = 2
        $btnSubmit.Text = "Submit"
        $btnSubmit.UseVisualStyleBackColor = $True

        $frmCaptcha.Controls.Add($btnSubmit)

        $txtCaptcha.DataBindings.DefaultDataSourceUpdateMode = 0
        $System_Drawing_Point = New-Object System.Drawing.Point
        $System_Drawing_Point.X = 46
        $System_Drawing_Point.Y = 68
        $txtCaptcha.Location = $System_Drawing_Point
        $txtCaptcha.Name = "txtCaptcha"
        $System_Drawing_Size = New-Object System.Drawing.Size
        $System_Drawing_Size.Height = 20
        $System_Drawing_Size.Width = 169
        $txtCaptcha.Size = $System_Drawing_Size
        $txtCaptcha.TabIndex = 1

        $frmCaptcha.Controls.Add($txtCaptcha)

        $imgCaptcha.AccessibleDescription = "CaptchaImage"
        $imgCaptcha.AccessibleName = "CaptchaImage"
        $imgCaptcha.DataBindings.DefaultDataSourceUpdateMode = 0



        $System_Drawing_Point = New-Object System.Drawing.Point
        $System_Drawing_Point.X = 72
        $System_Drawing_Point.Y = 12
        $imgCaptcha.Location = $System_Drawing_Point
        $imgCaptcha.Name = "imgCaptcha"
        $System_Drawing_Size = New-Object System.Drawing.Size
        $System_Drawing_Size.Height = 50
        $System_Drawing_Size.Width = 120
        $imgCaptcha.Size = $System_Drawing_Size
        $imgCaptcha.TabIndex = 0
        $imgCaptcha.TabStop = $False

        $frmCaptcha.Controls.Add($imgCaptcha)

        #endregion
        }

    Process
        {
        Write-Verbose "Getting Captcha image to present to user"
        $Captcha = Invoke-WebRequest -uri "$Global:BaseURL/captcha/$CaptchaIden"
        $imgCaptcha.Image = [System.Drawing.Image]::FromStream($Captcha.RawContentStream)

        #declare script block to run when submit button is clicked.
        $btnSubmit_OnClick= 
            {
            #set variable to show answer has been submitted
            $Submit = $true
            #close form window
            $frmCaptcha.Close()
            }
        #assign script block to submit button
        $btnSubmit.add_Click($btnSubmit_OnClick)

        #declare script block to run when new captcha button is clicked.
        $btnNewCaptcha_OnClick= 
        {
        #get new captcha image iden
        $params = @{
        "api_type" = $Global:ApiType
        }
        #request new captcha iden
        $CaptchaIden = Invoke-WebRequest -uri "$Global:BaseUrl/api/new_captcha" -Method Post -Body $Params -WebSession $GLOBAL:Session -UserAgent $Global:UserAgent | ConvertFrom-Json
        #get captch image
        $Captcha = Invoke-WebRequest -uri "$Global:BaseURL/captcha/$($CaptchaIden.json.data.iden)"
        #present image to user
        $imgCaptcha.Image = [System.Drawing.Image]::FromStream($Captcha.RawContentStream)
        }
        $btnNewCaptcha.add_Click($btnNewCaptcha_OnClick)

        #Load form
        $InitialFormWindowState = $frmCaptcha.WindowState
        $frmCaptcha.add_Load($OnLoadForm_StateCorrection)
        $frmCaptcha.ShowDialog() | Out-Null
        }
    
    End
        {
        #If the captcha answer has been submitted output it from the function
        IF ($Submit)
            {
            $output = [ORDERED] @{
                "Iden" = $CaptchaIden
                "Answer" = $txtCaptcha.Text.ToUpper()
                }
            New-Object PSObject -Property $Output
            }

        }

    }

#endregion

#region Debug-Errors
FUNCTION Debug-Errors
    {
    [CmdletBinding()]
    PARAM
        (
        $input
        )


    SWITCH -Regex ($input.json.errors)
        {
        "USER_REQUIRED"
            {
            [PSObject] @{
                "Action" = "Stop"
                "Message" = "No session information is avaialable, please run Connect-Reddit command to get seesion information"
                }
            }

        "HTTPS_REQUIRED" 
            {
            [PSObject] @{
                "Action" = "CONTINUE_WITH_HTTPS"
                "Message" = "This task is only avaialble over HTTPS"
                }
            }            
            
            

        "VERIFIED_USER_REQUIRED" 
            {
            
            }

        "NO_URL" 
            {
            
            }

        "BAD_URL" {}

        "BAD_CAPTCHA" 
            {
            [PSObject]@{
                "Action" = "TRY_WITH_CAPTCHA"
                "Message" = "Captcha was not answered correctly, re-submit with captcha answer"
                }
            }

        "BAD_USERNAME" {}

        "USERNAME_TAKEN" {}

        "USERNAME_TAKEN_DEL" {}

        "USER_BLOCKED" {}

        "NO_THING_ID" {}

        "TOO_MANY_THINGS_ID" {}

        "NOT_AUTHOR" {}

        "NOT_USER" {}

        "LOGGED_IN" {}

        "DELETED_LINK" {}

        "DELETED_COMMENT" {}

        "DELETED_THING" {}

        "BAD_PAASWORD" {}

        "WRONG_PASSWORD" {}

        "BAD_PASSWORD_MATCH" {}

        "NO_NAME" {}

        "NO_EMAIL" {}

        "NO_EMAIL_FOR_USER" {}

        "NO_TO_ADDRESS" {}

        "NO_SUBJECT" {}

        "USER_DOESENT_EXIST" {}

        "NO_USER" {}

        "INVALID_PREF" {}

        "BAD_NUMBER" {}

        "BAD_STRING" {}

        "BAD_BID" {}

        "ALREADY_SUB" {}

        "SUBREDDIT_EXISTS" {}

        "SUBREDDIT_NOTALLOWED" {}

        "SUBREDDIT_REQUIRED" {}

        "BAD_SR_NAME" {}

        "RATELIMIT" {}

        "QUOTA_FILLED" 
            {
            [PSObject] @{
                "Action" = "ADD_TO_QUEUE"
                "Message" = "You have tried that too many times, re-try in 1 hour"
                }
            }

        "SUBREDDIT_RATELIMIT" {}

        "EXPIRED" {}

        "DRACONIAN" {}

        "BANNED_IP" {}

        "BAD_CNAME" {}

        "USED_CNAME" {}

        "INVALID_OPTION" {}

        "CHEATER" {}

        "BAD_EMAILS" {}

        "NO_EMAILS" {}

        "TOO_MANY_EMAILS" {}

        "OVERSOLD" {}

        "BAD_DATE" {}

        "BAD_DATE_RANGE" {}

        "DATE_RANGE_TOO_LARGE" {}

        "BAD_FUTURE_DATE" {}

        "BAD_PAST_DATE" {}

        "BAD_ADDRESS" {}

        "BAD_CARD" {}

        "TOO_LONG" {}

        "NO_TEXT" {}

        "INVALID_CODE" {}

        "CLAIMED_CODE" {}

        "NO_SELFS" {}

        "NO_LINKS" {}

        "TOO_OLD" {}

        "BAD_CSS_NAME" {}

        "BAD_CSS" {}

        "BAD_REVISION" {}

        "TOO_MUCH_FLAIR_CSS" {}

        "BAD_FLAIR_TARGET" {}

        "CONFIRM" {}
       
        "CONFLICT" {}

        "NO_API" {}

        "DOMAIN_BANNED" {}

        "NO_OTP_SECRET" {}

        "NOT_SUPPORTED" {}

        "BAD_IMAGE" {}

        "DEVELOPER_ALREADY_ADDED" {}

        "TOO_MANY_DEVELOPERS" {}

        "BAD_HASH" {}

        "ALREADY_MODERATOR" {}

        "NO_INVITE_FOUND" {}

        "BID_LIVE" {}

        "TOO_MANY_CAMPAIGNS" {}

        "BAD_JASONP_CALLBACK" {}

        "INVALID_PERMISSION_TYPE" {}

        "INVALID_PERMISSIONS" {}

        "BAD_MULTI_PATH" {}

        "BAD_MULTI_NAME" {}

        "MULTI_NOT_FOUND" {}

        "MULTI_EXISTS" {}

        "MULTI_CANNOT_EDIT" {}

        "MULTI_TOO_MANY_SUBREDDITS" {}

        "MULTI_SPECIAL_SUBREDDIT" {}

        "JSON_PARSE_ERROR" {}

        "JSON_INVALID" {}

        "JOSN_MISSING_KEY" {}

        Default {}
        }
    }
#endregion

#region Help-Template

<# 
.SYNOPSIS


.DESCRIPTION


.PARAMETER  Credential


.PARAMETER Remember


.EXAMPLE


.INPUTS


.OUTPUTS

.NOTES
Created By: Dave Garnar/Davotronic5000

.LINK
http://davotronic5000.co.uk/blog
http://reddit.com/r/PowerShell
#>

#endregion