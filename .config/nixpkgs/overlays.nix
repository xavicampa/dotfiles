[
  # python overlay
  (final: prev:
    let
      pythonOverlay = pythonFinal: pythonPrev: {
        cfn-lint = pythonPrev.buildPythonPackage rec {
          pname = "cfn_lint";
          version = "1.40.2";
          format = "wheel";
          src = pythonPrev.fetchPypi rec {
            inherit pname version format;
            sha256 = "sha256-+kSjEBvY1/ZEvBRrip5j0PorZM1hyKdn5lxGkgZGJ3w=";
            dist = python;
            python = "py3";
          };
          patches = [ ];
          propagatedBuildInputs = [
            pythonPrev.jsonpatch
            pythonPrev.networkx
            pythonPrev.pyyaml
            pythonPrev.regex
            pythonPrev.aws-sam-translator
            pythonPrev.sympy
            pythonPrev.typing-extensions
          ];
        };
      };
    in {
      pythonPackagesExtensions = prev.pythonPackagesExtensions
        ++ [ pythonOverlay ];
      opencode =
        # REF: <https://github.com/NixOS/nixpkgs/issues/432051#issuecomment-3172569639>
        prev.opencode.overrideAttrs (o: {
          nativeBuildInputs = o.nativeBuildInputs or [ ]
            ++ [ final.makeWrapper ];
          postFixup =
            "  wrapProgram $out/bin/opencode \\\n    --set LD_LIBRARY_PATH \"${final.stdenv.cc.cc.lib}/lib\"\n";
        });
    })
]
