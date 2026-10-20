{
  description = "D3 mobile native toolchain";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          llvm
          dotnet-sdk_10
          spirv-cross
          python312
          uv
          git
          gnumake
          gnused
          gnugrep
        ];

        # The verifier shells out to llvm-mc/llvm-objdump; bind them to this
        # shell's LLVM so results cannot drift with a host toolchain.
        LLVM_BIN = "${pkgs.llvm}/bin";
        # dotnet resolves its runtime relative to DOTNET_ROOT, and the nix
        # package keeps the payload in share/dotnet rather than bin.
        DOTNET_ROOT = "${pkgs.dotnet-sdk_10}/share/dotnet";

        shellHook = ''
          # Keep dotnet/NuGet state inside the workspace: the CLI refuses to run
          # when its home sentinels cannot be created (observed EPERM on ~/.dotnet).
          export DOTNET_CLI_HOME="$PWD/work/.dotnet"
          export NUGET_PACKAGES="$PWD/work/.nuget/packages"
          export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
          # Xcode must provide the C/ObjC toolchain and xcrun: the Metal compiler
          # is an Xcode component, and nix's xcbuild xcrun shim plus the nix
          # apple-sdk (SDK 14.4) hide it. llvm-mc stays available via LLVM_BIN.
          unset SDKROOT DEVELOPER_DIR NIX_APPLE_SDK_VERSION
          PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vE -- '/nix/store/[^/]*(clang|llvm|xcbuild)[^/]*/bin' | paste -sd: -)
          export PATH
          # The nix compiler env would otherwise supply the nix apple-sdk and
          # libc++ headers to whatever clang wins; the host links Xcode frameworks.
          unset NIX_CFLAGS_COMPILE NIX_LDFLAGS NIX_CC NIX_BINTOOLS
          echo "llvm-mc: $("$LLVM_BIN/llvm-mc" --version | head -1)"
          echo "clang: $(clang --version | head -1)"
          echo "dotnet: $(dotnet --version)"
          echo "spirv-cross: $(spirv-cross --help 2>&1 | head -1)"
        '';
      };
    };
}
