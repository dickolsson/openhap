# OpenHAP Development Container

This devcontainer provides a complete Perl development environment for OpenHAP.

## Features

- **Perl 5.38**: Latest stable Perl version
- **All Dependencies**: Automatically installs all required Perl modules from `cpanfile`
- **Development Tools**: Perl::Critic (severity 4) and Perl::Tidy pre-configured
- **VS Code Extensions**: Perl language support with linting and formatting
- **Git & GitHub CLI**: Built-in version control tools

## Getting Started

### Prerequisites

- [Docker](https://www.docker.com/products/docker-desktop) or [Podman](https://podman.io/)
- [Visual Studio Code](https://code.visualstudio.com/)
- [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

### Opening the Project

1. Open VS Code
2. Open the OpenHAP project folder
3. When prompted, click "Reopen in Container" or run the command:
   - Press `F1` or `Ctrl+Shift+P` (Windows/Linux) / `Cmd+Shift+P` (Mac)
   - Type "Dev Containers: Reopen in Container"
   - Press Enter

The container will build and install all dependencies automatically (this may take a few minutes on first run).

## Development Workflow

### Running Tests

```bash
make test
```

### Linting Code

```bash
make lint
```

### Checking Formatting

```bash
make format
```

### Auto-fixing Formatting

```bash
make format-fix
```

### Installing Additional Dependencies

```bash
cpanm Module::Name
```

## VS Code Configuration

The devcontainer includes these pre-configured settings:

- **Tab Size**: 8 spaces (OpenBSD style)
- **Tabs**: Real tabs, not spaces (following style(9))
- **Perl Critic**: Enabled at severity 4
- **Perl Tidy**: Enabled with `.perltidyrc` configuration
- **Include Path**: `lib/` directory automatically included

## OpenBSD-Specific Notes

OpenHAP is designed for OpenBSD. While this devcontainer runs on Linux, keep in mind:

- The production environment is OpenBSD
- Some features like `pledge(2)` and `unveil(2)` are OpenBSD-specific
- The QEMU-based integration tests validate OpenBSD compatibility
- Always test on actual OpenBSD when possible

## Persistent Command History

Your bash command history is persisted across container rebuilds in `.devcontainer/bash_history`.

## Troubleshooting

### Container fails to build

1. Ensure Docker/Podman is running
2. Try rebuilding without cache:
   - `F1` → "Dev Containers: Rebuild Container Without Cache"

### Perl modules not found

Run the installation manually:
```bash
cpanm --installdeps .
```

### Extensions not working

Reload the window:
- `F1` → "Developer: Reload Window"

## Additional Resources

- [OpenHAP Documentation](../../README.md)
- [VS Code Dev Containers Documentation](https://code.visualstudio.com/docs/devcontainers/containers)
- [OpenBSD Style Guide](../../.github/copilot-instructions.md)
