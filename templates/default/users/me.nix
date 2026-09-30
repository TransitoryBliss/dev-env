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

      # One colour theme for the terminal, herdr, nvim and pi, instead of each
      # tool's own settings. The base's themes/palettes.json lists the names
      # (catppuccin-mocha, tokyonight-storm, gruvbox-light, rose-pine-dawn, ...).
      # A host file can override it, and `background` recolours just that host.
      # home.devEnv.theme.name = "gruvbox-dark";
      # home.devEnv.theme.background = "#211535";

      # Pi Session Manager: browse, search and resume agent sessions in a
      # browser, at http://psm.<machine>.localhost:8090 (needs proxy.enable below).
      # home.devEnv.sessionManager.enable = true;

      # Ideas and todos as markdown in a git repo of yours (create it first):
      # `note`, `idea "…"`, `todo "…"`, and a skill so agents use them too.
      # home.devEnv.notes.repo = "github.com/your-github-login/notes";

      # Secrets as environment variables (API keys for agent tools), from a
      # sops-encrypted file committed here. See the README's "Secrets".
      # home.devEnv.secrets = {
      #   sopsFile = ../secrets.yaml;
      #   env.LINEAR_API_KEY = "linear_api_key";
      #   # A different key in repos under one org (like git.overrides).
      #   # scopes."github.com/some-org".env.LINEAR_API_KEY = "some_org_linear_api_key";
      # };

      # Hourly restic backup of agent sessions (pi, Claude Code); needs the
      # restic_* keys in secrets.yaml. See the README's "Backups".
      # home.devEnv.backup = {
      #   enable = true;
      #   excludeScopes = [ "github.com/your-employer" ];  # never uploaded
      # };

      # MCP servers for pi: everywhere, and per org (like git.overrides).
      # `oauth = true` uses the callback port `make vm/ssh` forwards.
      # home.devEnv.mcp = {
      #   servers.context7.url = "https://mcp.context7.com/mcp";
      #   scopes."github.com/your-employer" = {
      #     inheritGlobal = false;  # only the employer's servers in its repos
      #     servers.notion = { url = "https://mcp.notion.com/mcp"; oauth = true; };
      #   };
      # };
    };

    # Local reverse proxy for web UIs in the machine, one hostname each on
    # port 8090. `make vm/ssh` forwards that port.
    # proxy.enable = true;

    timeZone = "UTC";
  };
}
