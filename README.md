# NanoClaw helper for Proxmox VE

This fork hosts the Proxmox VE helper for [NanoClaw](https://github.com/nanocoai/nanoclaw). It is maintained by the NanoClaw team and is not part of community-scripts; please do not report problems with it to the community-scripts project.

Run on the Proxmox VE host shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/glifocat/nanoclaw-proxmox/nanoclaw-helper-v2.1/ct/nanoclaw.sh)"
```

It creates an unprivileged Debian 13 LXC (2 cores, 8 GiB RAM, 40 GiB disk, nesting and keyctl on), installs Docker, Node.js 22 and the latest NanoClaw release in `/opt/nanoclaw`, and offers to start NanoClaw's setup wizard. To update NanoClaw later, run `update` inside the container. The helper is published from the `nanoclaw-helper-v2.1` tag, and the community-scripts engine it uses is pinned to a fixed commit.

To install NanoClaw `main` instead of the latest release (for testing unreleased changes), set `var_nanoclaw_ref=main`:

```bash
var_nanoclaw_ref=main bash -c "$(curl -fsSL https://raw.githubusercontent.com/glifocat/nanoclaw-proxmox/nanoclaw-helper-v2.1/ct/nanoclaw.sh)"
```

The layout is the same (`/opt/nanoclaw`, full Git history, `upstream` remote). On such an install, `update` moves to the latest `main` through NanoClaw's own staged updater and stops for `/update-nanoclaw` when `main` carries a breaking change.

Docs: [Installation](https://docs.nanoclaw.dev/installation). Support: [NanoClaw issues](https://github.com/nanocoai/nanoclaw/issues) or the [Discord](https://discord.gg/VDdww8qS42). Scripts: [`ct/nanoclaw.sh`](ct/nanoclaw.sh), [`install/nanoclaw-install.sh`](install/nanoclaw-install.sh).

---

# 🚧 ProxmoxVED Helper-Scripts (Development Repository)

**Warning: This repository is under active development and is not intended for production use. Changes may occur at any time!**



---

## 🔧 What is this?

This repository contains a collection of scripts for managing and automating Proxmox Virtual Environment (Proxmox VE). Originally created by [tteck](https://github.com/tteck), the project is now community-driven and continues to evolve.

---

## Want to help?

Follow [here](https://community-scripts.org/docs) to see our Documentations.

---

## 🚀 Development Status

- **⚠️ Unstable**: Features may be incomplete or subject to change.
- **📢 Community-driven**: Contributions and feedback are welcome.
- **🔄 Frequent updates**: Active development means rapid iterations and fixes.

---

## 💬 Get Involved

Join the discussion, contribute code, or report issues:

- **Discord**: [Join the Proxmox Helper Scripts Discord server](https://discord.gg/3AnUqsXnmK)
- **GitHub Issues**: [Report bugs or request features](https://github.com/community-scripts/ProxmoxVED/issues)

## 📜 License

This project is licensed under the [MIT License](LICENSE).

</br>
</br>
<p align="center">
  <i style="font-size: smaller;"><b>Proxmox</b>® is a registered trademark of <a href="https://www.proxmox.com/en/about/company">Proxmox Server Solutions GmbH</a>.</i>
</p>
