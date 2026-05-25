[
  # python overlay
  (final: prev: {
    _1password-gui = prev._1password-gui.overrideAttrs (old: {
      src = prev.fetchurl {
        url = old.src.url;
        hash = "sha256-JwiMi2iozP6jWSIUtgXla86aSAhuUob7snqtUbeXPpI=";
      };
    });

    _1password-cli = prev._1password-cli.overrideAttrs (old: {
      src = prev.fetchzip {
        url = old.src.url;
        hash = "sha256-sbydXPoT0Vo3r2gyZBdl4OMtOejbhvra5JM4wB6Ex5s=";
        stripRoot = false;
      };
    });
  })
]
