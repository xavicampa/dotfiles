[
  # python overlay
  (final: prev:
    let
      pythonOverlay = pythonFinal: pythonPrev: {
        cfn-lint = pythonPrev.buildPythonPackage rec {
          pname = "cfn_lint";
          version = "1.34.2";
          format = "wheel";
          src = pythonPrev.fetchPypi rec {
            inherit pname version format;
            sha256 = "sha256-tSnh91ZFWn1F890FhNA1qPswzzC4qVpJLRGig05oJnM=";
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
    in
    {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [ pythonOverlay ];
    })
]
