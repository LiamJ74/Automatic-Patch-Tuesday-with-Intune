# ✨ Fully Automated Patch Tuesday Deployment for Intune ✨

## 🚀 Goal

This project provides a single, powerful PowerShell script to perform a **true end-to-end automated deployment** of monthly Patch Tuesday updates.

The script handles everything: finding the latest KBs, downloading them, packaging them, and creating or updating the application in Intune, ready for deployment.

## 🌟 Key Features

-   **Auto-Discovery:** Automatically finds the latest Cumulative Updates for the Windows builds you define (x64 and arm64).
-   **Auto-Dependency:** Automatically downloads the `IntuneWinAppUtil.exe` packaging tool if it's missing.
-   **Intelligent Publishing:**
    -   **Creates** the app if it doesn't exist for the current month.
    -   **Updates** assignments if the app for the current month already exists, ensuring your deployment rings are always in sync with the parameters you provide.
-   **Auto-Packaging:** Automatically creates the `.intunewin` package.
-   **Auto-Assignment:** Automatically assigns the application to your specified deployment groups.
-   **Non-Interactive:** Uses an Azure AD App Registration for a secure, unattended connection to Microsoft Graph.

## 🛠️ Prerequisites

Before you begin, ensure you have the following:

1.  **PowerShell 5.1 or higher.**
2.  **Required PowerShell Modules:** Install them by running these commands in PowerShell:
    ```powershell
    Install-Module -Name MSCatalogLTS -Force
    Install-Module -Name IntuneWin32App -Force -Repository PSGallery
    ```
3.  **An Azure AD App Registration:** The script needs an identity in Azure to interact with Intune securely.

### How to Create the App Registration

1.  Navigate to the **Azure portal** > **Azure Active Directory** > **App registrations**.
2.  Click **New registration**. Give it a descriptive name (e.g., `Intune-Patch-Tuesday-Automation`).
3.  Note down the **Application (client) ID** and **Directory (tenant) ID**.
4.  Go to the **Certificates & secrets** tab.
    -   Click **New client secret**.
    -   Give it a description and an expiry date.
    -   **Immediately copy the secret's *Value***. This is your only chance to see it.
5.  Go to the **API permissions** tab.
    -   Click **Add a permission** > **Microsoft Graph**.
    -   Select **Application permissions**.
    -   Search for and add the following permissions:
        -   `DeviceManagementApps.ReadWrite.All`: Allows the script to create and manage applications and their assignments.
        -   `Group.Read.All`: Allows the script to find your assignment groups.
    -   Click **Add permissions**.
6.  Finally, click **Grant admin consent for [Your Tenant]**. The status for both permissions should change to "Granted".

## 🏃‍♀️ How to Run the Script

1.  **Configure Target Builds:** Open `Scripts/Generate-KBMap.ps1` and edit the `$TargetBuilds` variable to include the Windows builds you manage.
2.  **Execute the script from the project root directory** with your parameters. The script will use the current month and year to name the application (e.g., "Patch Tuesday - August 2025").

### Example

```powershell
./Scripts/Generate-KBMap.ps1 `
    -ClientId "your-application-client-id" `
    -ClientSecret "your-client-secret-value" `
    -TenantId "your-directory-tenant-id" `
    -Publisher "My IT Department" `
    -GroupTest "object-id-of-pilot-group" `
    -GroupRing1 "object-id-of-ring1-group"
```

### All Available Parameters

-   `ClientId`, `ClientSecret`, `TenantId`: (Mandatory) Your App Registration details.
-   `AppName`: The name of the application. Defaults to "Patch Tuesday - [Current Month Year]".
-   `Description`: The application description.
-   `Publisher`: The publisher name.
-   `GroupTest`, `GroupRing1`, `GroupRing2`, `GroupRing3`, `GroupLast`: (Optional) The Object IDs of the Azure AD groups for assignment.

## ⚙️ The Workflow (What the Script Does)

1.  **Connects to Intune:** Authenticates to Microsoft Graph using the `IntuneWin32App` module and your App Registration.
2.  **Checks for Existing App:** Searches for an app with the name for the current month (e.g., "Patch Tuesday - August 2025").
3.  **If App Exists:**
    -   The script confirms the app exists and proceeds to update its assignments.
4.  **If App Does Not Exist:**
    -   The script downloads all required KBs, packages them into an `.intunewin` file (along with the installer and detection scripts), and creates a new application in Intune.
5.  **Syncs Assignments:**
    -   The script retrieves all current assignments for the application.
    -   It **removes all of them** to ensure a clean state.
    -   It then **adds new assignments** based on the `-Group...` parameters you provided in the command line. This ensures the app is assigned to exactly the groups you specified in the last run.

Enjoy your fully automated patching! 🥳
