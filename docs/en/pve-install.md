# Proxmox VE (PVE) Installation Guide

[Back to README](./README.md) | [中文](../zh/pve-install.md) | English

This guide is for users installing a Landscape Mini image on **Proxmox VE (PVE)** for the first time. It walks through the process step by step from scratch.

## Read this first

If you just want to get it running as quickly as possible, **prefer using a prebuilt image from the repository Release first**.

Only use the [Custom Build Guide](./custom-build.md) when one of the following applies:

- You need a custom subnet
- You need to change LAN / DHCP parameters
- You need to customize passwords, accounts, or other build parameters

Recommended order:

1. If the official Release image works for your case, install it directly first
2. If you need custom network parameters, use `Custom Build`
3. By default, the recommended choice is a build **with Docker included**
4. Prefer `output_formats=img,ova`
5. In PVE, prefer **OVA import** first
6. If OVA is not convenient, manually import `.img` / `.img.gz` instead

---

## 1. Recommended build choice

If this is your first time using it, the recommended selection in `Custom Build` is:

- `base_system=debian`
- `include_docker=true`
- `output_formats=img,ova`

Why this is recommended:

- `debian` is generally more stable in terms of compatibility and is a good default choice
- `include_docker=true` matches common real-world usage better and avoids installing Docker later
- `img,ova` produces both:
  - `.ova`: convenient for one-click import in PVE
  - `.img`: useful for manual import and fallback troubleshooting

> If you do not need custom network parameters, prefer using a prebuilt image from the repository Release directly.  
> If you are using `Custom Build`, copy the download link from your own workflow artifact or fixed release page.

---

## 2. Before you begin

Please make sure:

- You have a working PVE node
- You already have the build output:
  - Recommended: `.ova`
  - Fallback: `.img` or `.img.gz`
- You know which storage pool to import into
- You can log in to the PVE Web UI
- If you are using manual import, you can also log in to the PVE host over SSH

---

## 3. Very important: NIC model must match when using multiple NICs

If your VM has multiple NICs, make sure their **NIC model is consistent**.

For example:

- all `E1000`
- or all `VirtIO`
- or all the same other model

### Why must they match?

If multiple NICs use different models, interface ordering inside the system may become inconsistent. For example:

- You expect WAN to be `eth0`
- But after boot, the LAN / WAN order is reversed
- The final result may look like this:
  - `eth0` in `ip a` does not get an IP address
  - or the `eth0` / `eth1` order does not match expectations

### How do I fix this if it happens?

To fix it:

1. Open the VM's **Hardware** page in PVE
2. Check the model/type of all NICs
3. Change them to the **same model**
4. **Restart the VM**

> Mixing different NIC models is currently not recommended, because it can easily cause interface ordering issues.

---

## 4. Method 1: Import OVA directly by URL (recommended)

The preferred approach is to use the `.ova` download link from the repository's official Release directly.

If you are using `Custom Build`, go to your own workflow artifact or fixed release page and copy the `.ova` download link there.

### Step 1: Confirm the storage pool allows import

Go to:

**Datacenter -> Storage -> target storage entry (for example `local`)**

Click Edit and make sure the storage has these content types enabled:

- `Import`
- `Disk image`

Both must be enabled, otherwise the import may fail.

---

### Step 2: Open the storage import page

Go to:

**Datacenter -> Storage -> target storage entry (for example `local`) -> Content**

Find the **Download from URL / Import** entry.

---

### Step 3: Copy the download link

If you are using the official Release, copy the download link for the target `.ova` file directly.

Then paste that link into the PVE URL import field.

If you are using `Custom Build`:

- Go to your own workflow artifact page or fixed release page
- Find the corresponding `.ova` file
- Copy its download link into PVE

---

### Step 4: Start download and import

After confirming the target storage, run the import.

When it finishes, PVE will have an image file that can be used by a VM.

---

### Step 5: Check the imported VM configuration

After the import finishes, it is recommended to check:

- boot mode
- disk controller
- bridge assignment
- CPU type
- NIC model

Notes:

- For **older CPUs**, `host` mode is usually the preferred choice for compatibility
- If you want CPU type `host`, set it manually after import
- PVE currently does not reliably inherit `CPU type=host` from OVF/OVA metadata

---

## 5. Method 2: Manually import `.img` or `.img.gz`

If you do not want to use OVA, or OVA import is not convenient, you can import the raw image instead.

### Step 1: Create the VM in PVE first

When creating the VM:

- Fill in the VM name, ID, and other settings normally
- **Do not add a disk**
- For the other settings, you can keep the defaults or use your preferred values

Key point:

- **Do not select a disk when creating the VM**
- We will manually import the `.img` afterward

---

### Step 2: Put the `.img` or `.img.gz` file on the PVE host

There are two common methods.

#### Method A: Download it directly on the PVE host

If you are using the official Release, first copy the official `.img.gz` download link, then SSH into the PVE host and run:

```bash
wget -O landscape-mini.img.gz "<official Release download URL>"
```

If you are using `Custom Build`, copy the `.img` / `.img.gz` download link from your own workflow artifact or fixed release page, then use the same download steps.

If the downloaded file is `.img.gz`, decompress it first:

```bash
gunzip -f landscape-mini.img.gz
```

After decompression, you will get:

- `landscape-mini.img`

If you downloaded `.img` directly, no decompression is needed.

#### Method B: Upload it manually from your local machine

You can upload it to any directory on the PVE host using:

- `scp`
- `rsync`
- an SFTP tool
- any other upload method you prefer

For example:

```bash
scp landscape-mini.img root@<pve-host>:/root/
```

If you upload `.img.gz`, decompress it on the PVE host afterward:

```bash
gunzip -f /root/landscape-mini.img.gz
```

---

### Step 3: Import the disk into PVE

Log in to the PVE host and run:

```bash
qm importdisk <vmid> /path/to/landscape-mini.img <storage>
```

For example:

```bash
qm importdisk 101 /root/landscape-mini.img local-lvm
```

Where:

- `<vmid>`: VM ID
- `/path/to/landscape-mini.img`: image path
- `<storage>`: target storage pool name

---

### Step 4: Attach the imported disk in the VM hardware page

Go back to the PVE Web UI:

**VM -> Hardware**

Find the imported disk and attach it to the position you want to use (for example `scsi0` or `sata0`).

Then set:

- boot order
- that disk as the boot disk

---

## 6. First boot checks

After starting the VM, it is recommended to check the following first.

### 1. Is the NIC order correct?

Run:

```bash
ip a
```

Pay special attention to:

- whether `eth0` got the expected IP address
- whether `eth1` matches the other NIC you intended
- whether WAN / LAN match your bridge wiring and configuration

If you see:

- `eth0` has no IP
- or the `eth0` / `eth1` order is unexpected

Go back to PVE and first check whether all NICs use the same model.

---

## 7. Disk expansion

Landscape Mini automatically expands the root partition to the current disk size at boot.

This means:

- on the **first boot**, it expands to the current disk size automatically
- if you enlarge the disk later in PVE, it will continue expanding on the **next reboot**

### How to expand the disk in PVE

Go to:

**VM -> Hardware -> select disk -> Disk Action -> Resize**

Enter the amount of extra space you want to add, for example:

- it is recommended to add **16G** first

If you need more later, you can expand it again.

### Notes

Hot expansion is **not currently applied immediately**.

That means:

- after resizing the disk in PVE
- you need to **restart the VM**
- the expansion will only take effect on the next boot

---

## 8. FAQ

### 1. Why does URL import fail in PVE?

First make sure the target storage has these content types enabled:

- `Import`
- `Disk image`

Path:

**Datacenter -> Storage -> target storage entry (for example `local`) -> Edit -> Content**

### 2. What should I do if I get this error?

```text
sata0: import working storage 'local' does not support 'images' content type or is not filebased
```

This usually means:

- the selected working storage does not have `Disk image` enabled
- or it is not a file-based storage suitable for this import flow

How to fix it:

1. Go to  
   **Datacenter -> Storage -> local -> Edit**
2. Make sure these content types are enabled:
   - `Import`
   - `Disk image`
3. If it still fails, use a directory-based storage that supports file-based import, or switch to manual `.img` import instead

### 3. Why does `eth0` in `ip a` not have an IP address after boot?

Check these first:

- whether the VM has multiple NICs
- whether all NICs use the same model

If they are mixed, for example:

- one `E1000`
- one `VirtIO`

then you may get:

- `eth0` / `eth1` order mismatch
- `eth0` not receiving the expected IP

How to fix it:

1. Change all NICs to the same model
2. Restart the VM
3. Run `ip a` again and check the result

### 4. What should I check after OVA import?

At minimum, check:

- boot mode
- disk controller
- bridge assignment
- CPU type
- whether all NICs use the same model

For older CPUs, it is recommended to set CPU type to `host` manually first.

### 5. Why does the disk size not increase immediately after import?

Because expansion currently takes effect **at boot time**.

If you just used Resize in PVE:

- you need to restart the VM
- then the expansion will happen automatically on the next boot
