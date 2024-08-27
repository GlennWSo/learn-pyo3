{
  inputs = {
    nixpkgs.url = "github:NixOs/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-filter.url = "github:numtide/nix-filter";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    rust-overlay,
    crane,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {inherit overlays system;};

        python = pkgs.python312;
        pypkgs = pkgs.python312Packages;

        rust = pkgs.rust-bin.stable.latest.default.override {
          # targets = ["thumbv7em-none-eabihf"];
        };
        craneLib = (crane.mkLib pkgs).overrideToolchain rust;

        fs = pkgs.lib.fileset;
        srcFiles = fs.unions [
          (fs.fileFilter (file: file.hasExt "toml") ./.)
          (fs.fileFilter (file: file.hasExt "rs") ./src)
          (fs.fileFilter (file: file.name == "Cargo.lock") ./.)
          # (fs.fileFilter (file: file.name == "Cargo.toml") ./.)
        ];
        src = fs.toSource {
          root = ./.;
          fileset = srcFiles;
        };
        cargoArtifacts = craneLib.buildDepsOnly {
          inherit src;
          pname = "deps";
          buildInputs = [pkgs.python312];
          # version = "0.1.0";
          doCheck = false;
        };
        mycrate = craneLib.buildPackage {
          inherit src cargoArtifacts;
          buildInputs = [pkgs.python312];
        };
        crate_wheel = mycrate.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [pkgs.maturin];
          buildPhase =
            old.buildPhase
            + ''
              maturin build --offline --target-dir ./target
            '';
          # installPhase =
          #   old.installPhase
          #   + ''
          #     cp target/wheels/${project_name}-${project_version}-${wheel_tail}.whl $out/
          #   '';
        });
        pyDevSet = with pypkgs; [
          venvShellHook
          pyvista
          # numpy
        ];
      in {
        # packages.default = pkgs.hello;
        packages.default = crate_wheel;
        dbg.src = src;
        devShells.default = pkgs.mkShell {
          venvDir = ".venv";
          buildInputs = with pkgs;
            [
              maturin
              rust
            ]
            ++ pyDevSet;
        };
        # devShells.default = craneLib.devShell {
        #   name = "rspy";
        #   inputsFrom = [mycrate];
        #   packages = [
        #     pkgs.maturin
        #     pypkgs.setuptools-rust
        #   ];
        # };
      }
    );
}
