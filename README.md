# ✨ Fully Automated Patch Tuesday Deployment for Intune ✨

## 🚀 Goal

This project provides a powerful and flexible PowerShell solution to automate the deployment of monthly Patch Tuesday updates via Intune.

It supports two distinct operational modes, allowing you to choose the best strategy for your environment:
1.  **On-Demand (Default):** Creates an ultra-lightweight Intune package. Each client device downloads its specific update directly from Microsoft, saving massive amounts of Intune bandwidth and storage.
2.  **Pre-Package:** Downloads all necessary update files ahead of time and bundles them into a traditional, self-contained Intune package. This is ideal for environments where clients have restricted internet access.

## 🌟 Key Features

-   **Dual-Mode Operation:** Choose between bandwidth-optimized on-demand downloads or self-contained pre-packaged deployments.
-   **Auto-Discovery:** Automatically finds the latest Cumulative Updates metadata for the Windows builds you define.
-   **Intelligent Publishing:** Creates a new Intune application for the current month or updates assignments if one already exists.
-   **Auto-Packaging:** Automatically creates either a lightweight or a full `.intunewin` package.
-   **Auto-Assignment:** Assigns the application to your deployment groups with optional staggering.
-   **Non-Interactive:** Uses an Azure AD App Registration for secure, unattended authentication.

## 📖 Choosing Your Download Method

You can select the deployment mode using the `-DownloadMethod` parameter in the `Generate-KBMap.ps1` script.

### `OnDemand` (Default Mode)
-   **How it works:** Creates a tiny Intune package with only scripts and a list of needed updates. Each client downloads its own `.msu` file from Microsoft at installation time.
-   **Pros:**
    -   ✅ **Extremely small `.intunewin` file size** (kilobytes).
    -   ✅ **Massive savings** on Intune storage and distribution bandwidth.
    -   ✅ Very fast to package and upload to Intune.
-   **Cons:**
    -   ❌ **Requires internet access for all clients** to reach the Microsoft Update Catalog.
    -   ❌ **Requires the `MSCatalogLTS` PowerShell module to be pre-installed on all clients.**
    -   ❌ Installation time on the client is longer as it includes a download.

### `Prepackage`
-   **How it works:** Downloads all required `.msu` files to your local machine and bundles them into a large, self-contained Intune package.
-   **Pros:**
    -   ✅ **Works for clients with no or restricted internet access** (as long as they can reach Intune).
    -   ✅ **No client-side dependencies** other than PowerShell itself.
    -   ✅ Faster installation on the client as the file is already local.
-   **Cons:**
    -   ❌ **Very large `.intunewin` file size** (potentially gigabytes).
    -   ❌ **Consumes significant Intune bandwidth** and storage.
    -   ❌ Slower to package and upload to Intune.

---

## 🛠️ Prerequisites

### For the Admin / Execution Environment

1.  **PowerShell 5.1 or higher.**
2.  **Required PowerShell Modules:**
    ```powershell
    Install-Module -Name MSCatalogLTS -Force
    Install-Module -Name IntuneWin32App -Force -Repository PSGallery
    ```
3.  **An Azure AD App Registration** with `DeviceManagementApps.ReadWrite.All` and `Group.Read.All` API permissions.

### For Client Devices
-   **For `OnDemand` mode:**
    1.  PowerShell 5.1 or higher.
    2.  The `MSCatalogLTS` module must be installed.
    3.  Internet access to the Microsoft Update Catalog.
-   **For `Prepackage` mode:**
    1.  No special prerequisites beyond the ability to receive Intune applications.

---

## 🏃‍♀️ How to Run the Script

1.  **Choose your download method.**
2.  **Ensure all prerequisites for your chosen method are met.**
3.  **Configure Target Builds:** Open `Scripts/Generate-KBMap.ps1` and edit the `$TargetBuilds` variable.
4.  **Unblock the Script File:**
    ```powershell
    Unblock-File -Path ./Scripts/Generate-KBMap.ps1
    ```
5.  **Execute the script** with your parameters. Use `-DownloadMethod` to select your mode.

### Example (`OnDemand` mode)
```powershell
./Scripts/Generate-KBMap.ps1 `
    -DownloadMethod 'OnDemand' `
    -ClientId "your-app-id" `
    -TenantId "your-tenant-id" `
    -GroupTest "object-id-of-pilot-group"
```

### Example (`Prepackage` mode)
```powershell
./Scripts/Generate-KBMap.ps1 `
    -DownloadMethod 'Prepackage' `
    -ClientId "your-app-id" `
    -TenantId "your-tenant-id" `
    -GroupTest "object-id-of-pilot-group"
```

## ⚙️ How It Works

1.  **KB Metadata Discovery:** `Generate-KBMap.ps1` searches the Microsoft Catalog for updates based on your `$TargetBuilds`.
2.  **Mode-Dependent Action:**
    -   If in **`Prepackage`** mode, it downloads all the `.msu` files into a `KBs` folder.
    -   If in **`OnDemand`** mode, it skips the download.
3.  **Creating the KB Map:** It generates a `kbmap.csv` manifest. The content differs based on the mode (`FileName` vs `Title`).
4.  **Packaging & Publishing:** It creates an Intune application, bundling the scripts and either just the manifest (`OnDemand`) or the manifest plus all `.msu` files (`Prepackage`).
5.  **Client-Side Installation (`Install-KB.ps1`):**
    -   The script on the client inspects `kbmap.csv` to see which mode to use.
    -   In **`Prepackage`** mode, it installs the `.msu` file already present in the package.
    -   In **`OnDemand`** mode, it uses the local `MSCatalogLTS` module to download the correct `.msu` file, then installs it.
6.  **Detection (`Detection.ps1`):** Before installation, Intune uses this script to check the device's UBR against `kbmap.csv` to see if the update is already installed, preventing unnecessary work in both modes.

Enjoy your flexible automated patching! 🥳
