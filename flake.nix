{
  description = "A basic flake using uv2nix";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/684a8fe32d4b7973974e543eed82942d2521b738";
    uv2nix.url = "github:/pyproject-nix/uv2nix";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    #uv2nix_hammer_overrides.url = "/project/builds/hammer_build_local-attention_1.9.15/overrides";
    #uv2nix_hammer_overrides.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-nix.url = "github:/pyproject-nix/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    nixpkgs,
    uv2nix,
    #uv2nix_hammer_overrides,
    #pyproject-nix,
    pyproject-build-systems,
    ...
  }: let
    #inherit (nixpkgs) lib;
    lib = nixpkgs.lib // {match = builtins.match;};

    pyproject-nix = uv2nix.inputs.pyproject-nix;
    workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = ./.;};

    pkgs = import nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    defaultPackage = let
      # Generate overlay
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };
      #pyprojectOverrides = uv2nix_hammer_overrides.overrides_strict pkgs;
      pyprojectOverrides = final: prev: {
        nvidia-cusolver-cu12 = prev.nvidia-cusolver-cu12.overrideAttrs (old: {
          buildInputs =
            old.buildInputs
            or []
            ++ [
              pkgs.cudaPackages.libcublas
              pkgs.cudaPackages.libcusparse
              pkgs.cudaPackages.libnvjitlink
            ];
        });
        nvidia-cusparse-cu12 = prev.nvidia-cusparse-cu12.overrideAttrs (old: {
          buildInputs = old.buildInputs or [] ++ [pkgs.cudaPackages.libnvjitlink];
        });
        torch = prev.torch.overrideAttrs (
          old: {
            buildInputs =
              old.buildInputs
              or []
              ++ (pkgs.lib.optionals (
                (builtins.trace pkgs.stdenv.hostPlatform.system pkgs.stdenv.hostPlatform.system) == "x86_64-linux"
              ) [pkgs.cudaPackages.cuda_cudart])
              ++ [
                pkgs.cudaPackages.cuda_cupti
                pkgs.cudaPackages.cuda_nvrtc
                pkgs.cudaPackages.cudnn
                pkgs.cudaPackages.libcublas
                pkgs.cudaPackages.libcufft
                pkgs.cudaPackages.libcurand
                pkgs.cudaPackages.libcusolver
                pkgs.cudaPackages.libcusparse
                pkgs.cudaPackages.nccl
              ];
          }
        );
      };
      python = pkgs.python312;
      spec = {
        uv2nix-hammer-app = [];
      };

      # Construct package set
      pythonSet =
        # Use base package set from pyproject.nix builders
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        })
        .overrideScope
        (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            pyprojectOverrides
          ]
        );
      # Override host packages with build fixups
    in
      # Render venv
      pythonSet.mkVirtualEnv "test-venv" spec;
  in {
    packages.x86_64-linux.default = defaultPackage;
    # TODO: A better mkShell withPackages example.
  };
}
