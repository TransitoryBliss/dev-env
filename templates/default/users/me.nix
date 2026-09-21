# Who you are. Shared by all your hosts; a host can add to or change it.
{
  devEnv = {
    user = {
      name = "me";

      # Public keys allowed to SSH into VM hosts, e.g. your laptop's ~/.ssh/id_ed25519.pub.
      sshKeys = [ ];

      # Home-manager config. Git picks name, email and SSH key per repo:
      # the default everywhere, an override for repos under a given owner.
      home.devEnv.git = {
        default = {
          account = "your-github-login";
          name = "Your Name";
          email = "12345+your-github-login@users.noreply.github.com";
        };
        # overrides."github.com/your-employer" = {
        #   account = "your-work-login";
        #   name = "Your Name";
        #   email = "you@employer.com";
        # };
      };

      # Colours an interactive zsh writes to its terminal, so the palette is
      # part of this config instead of the terminal emulator's own settings.
      # "gruvbox-dark", "catppuccin-mocha", or left out to change nothing.
      # home.devEnv.terminalPalette = "gruvbox-dark";
    };

    timeZone = "UTC";
  };
}
