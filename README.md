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

## 🔒 Security Note: Handling the Client Secret

> **Warning:** Passing secrets directly on the command line is a security risk. Your secret can be stored in PowerShell history files in plain text.

The recommended way to provide the client secret is to use an environment variable.

**On Windows:**
```powershell
$env:INTUNE_CLIENT_SECRET = "your-client-secret-value"
```

**On Linux/macOS:**
```bash
export INTUNE_CLIENT_SECRET="your-client-secret-value"
```

The script will automatically detect and use this environment variable. If you must use the `-ClientSecret` parameter, do so with caution in a secure, ephemeral environment.

## 🏃‍♀️ How to Run the Script

1.  **Set the Environment Variable:** For security, provide the client secret via the `INTUNE_CLIENT_SECRET` environment variable (see the security note above).
2.  **Configure Target Builds:** Open `Scripts/Generate-KBMap.ps1` and edit the `$TargetBuilds` variable to include the Windows builds you manage.
3.  **Execute the script from the project root directory** with your parameters. The script will use the current month and year to name the application (e.g., "Patch Tuesday - August 2025").

### Example

This example assumes you have set the `INTUNE_CLIENT_SECRET` environment variable.

```powershell
./Scripts/Generate-KBMap.ps1 `
    -ClientId "your-application-client-id" `
    -TenantId "your-directory-tenant-id" `
    -Publisher "My IT Department" `
    -GroupTest "object-id-of-pilot-group" `
    -GroupRing1 "object-id-of-ring1-group"
```

### All Available Parameters

-   `ClientId`, `TenantId`: (Mandatory) Your App Registration details.
-   `ClientSecret`: (Optional) The client secret. **It is recommended to use the `INTUNE_CLIENT_SECRET` environment variable instead.**
-   `AppName`: The name of the application. Defaults to "Patch Tuesday - [Current Month Year]".
-   `Description`: The application description.
-   `Publisher`: The publisher name.
-   `GroupTest`, `GroupRing1`, `GroupRing2`, `GroupRing3`, `GroupLast`: (Optional) The Object IDs of the Azure AD groups for your deployment rings. `GroupLast` is intended for the final, broadest deployment ring.

## ⚙️ How It Works: The Workflow and Key Files

The process is orchestrated by `Generate-KBMap.ps1` and involves several key files that work together.

1.  **KB Discovery and Download:**
    -   The main script (`Generate-KBMap.ps1`) searches the Microsoft Update Catalog for the latest cumulative updates based on the OS builds defined in the `$TargetBuilds` variable.
    -   It downloads the relevant update files (`.msu`) into the `KBs/` directory.

2.  **Creating the KB Map:**
    -   As it downloads updates, the script generates a `kbmap.csv` file. This file acts as a manifest, mapping each OS build to its corresponding KB number and MSU filename.

3.  **Packaging for Intune:**
    -   If Intune publishing is enabled (by providing a `ClientId`), the script creates an `.intunewin` package for deployment.
    -   This package contains:
        -   All downloaded `.msu` files from the `KBs/` directory.
        -   The `kbmap.csv` manifest file.
        -   The `Install-KB.ps1` script, which will run on each client machine.
        -   The `Detection.ps1` script, used by Intune to see if the update is already installed.

4.  **The Installer (`Install-KB.ps1`):**
    -   This script is the installation logic that runs on each user's device.
    -   It determines the device's OS build, looks up the correct KB in the included `kbmap.csv`, and installs the right `.msu` file using `wusa.exe`.
    -   It returns exit codes back to Intune (e.g., `0` for success, `3010` for success with reboot required) to ensure accurate reporting.

5.  **The Detection Rule (`Detection.ps1`):**
    -   Before installing, Intune uses this script to check if the required update is already present.
    -   Like the installer, it uses the `kbmap.csv` to find the correct KB for the device's build and checks if it's installed. This prevents unnecessary reinstallations.

6.  **Intune Application Management:**
    -   The script searches for an app in Intune with the name for the current month (e.g., "Patch Tuesday - August 2025").
    -   **If the app exists,** it simply updates the group assignments.
    -   **If the app does not exist,** it creates a new one, uploading the `.intunewin` package and configuring it with the installer and detection logic.

7.  **Assignment Sync:**
    -   To ensure a clean state, the script **removes all existing assignments** from the application.
    -   It then adds fresh assignments based on the `-Group...` parameters you provided, creating a staggered deployment with increasing delays for each ring.

Enjoy your fully automated patching! 🥳
