# ✨ Fully Automated Patch Tuesday Deployment for Intune ✨

## 🚀 Goal

This project provides a single, powerful PowerShell script to perform a **true end-to-end automated deployment** of monthly Patch Tuesday updates.

The script handles everything: finding the latest KBs, downloading them, packaging them into an `.intunewin` file, and creating and assigning a new application in Intune, ready for your pilot ring.

## 🌟 Key Features

-   **Auto-Discovery:** Automatically finds the latest Cumulative Updates for the Windows builds you define.
-   **Auto-Dependency:** Automatically downloads the `IntuneWinAppUtil.exe` packaging tool if it's missing.
-   **Auto-Packaging:** Automatically creates the `.intunewin` package.
-   **Auto-Publishing:** Automatically creates a **new application** in Intune each month. This is a best practice for version tracking.
-   **Auto-Assignment:** Automatically assigns the new application to your specified deployment groups (e.g., Pilot, Broad, Prod).
-   **Non-Interactive:** Uses an Azure AD App Registration for a secure, unattended connection to Microsoft Graph.

## 🛠️ Prerequisites

Before you begin, ensure you have the following:

1.  **PowerShell 5.1 or higher.**
2.  **Required PowerShell Modules:** Install them by running these commands in PowerShell:
    ```powershell
    Install-Module -Name MSCatalogLTS -Force
    Install-Module -Name IntuneWin32App -Force
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
        -   `DeviceManagementApps.ReadWrite.All`: Allows the script to create and manage applications.
        -   `Group.Read.All`: Allows the script to find your assignment groups.
    -   Click **Add permissions**.
6.  Finally, click **Grant admin consent for [Your Tenant]**. The status for both permissions should change to "Granted".

## 🏃‍♀️ How to Run the Script

1.  **Configure Target Builds:** Open `Scripts/Generate-KBMap.ps1` and edit the `$TargetBuilds` variable to include the Windows builds you manage.
2.  **Execute the script from the project root directory** with your parameters.

### Example

```powershell
./Scripts/Generate-KBMap.ps1 `
    -ClientId "your-application-client-id" `
    -ClientSecret "your-client-secret-value" `
    -TenantId "your-directory-tenant-id" `
    -AppName "Patch Tuesday - $(Get-Date -Format 'MMMM yyyy')" `
    -Publisher "My IT Department" `
    -GroupPilot "object-id-of-pilot-group" `
    -GroupBroad "object-id-of-broad-deployment-group"
```

### All Available Parameters

-   `ClientId`, `ClientSecret`, `TenantId`: (Mandatory) Your App Registration details.
-   `AppName`: The name of the application to be created in Intune. Defaults to "Patch Tuesday - [Current Month Year]".
-   `Description`: The application description.
-   `Publisher`: The publisher name.
-   `GroupPilot`, `GroupBroad`, `GroupProd`: (Optional) The Object IDs of the Azure AD groups for assignment. You can use one or more.

## ⚙️ The Workflow (What the Script Does)

1.  **Downloads KBs:** Searches the Microsoft Update Catalog for the latest Cumulative Updates for your target builds and downloads the `.msu` files into the `KBs/` folder.
2.  **Creates `kbmap.csv`:** Generates a mapping file for the client script to use.
3.  **Checks for Packager:** Ensures `IntuneWinAppUtil.exe` is present in the `Tools/` folder, downloading it if necessary.
4.  **Generates Detection Script:** Creates a `Detection.ps1` script on the fly. This script is used by Intune to check if the correct KB is already installed.
5.  **Packages:** Compresses the `Scripts/` and `KBs/` folders along with `kbmap.csv` into an `.intunewin` file.
6.  **Publishes to Intune:** Connects to Microsoft Graph and uses the `IntuneWin32App` module to upload the package, create the new application with your specified metadata, and assign it to your groups.

Enjoy your fully automated patching! 🥳
