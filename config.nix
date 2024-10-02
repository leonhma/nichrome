{pkgs, system, lib, ...}: {
  system.stateVersion = "24.11";
  networking = { hostName = "nixos"; };
  system.activationScripts.crostiniSetup = ''
    # Create empty /etc/gshadow file
    touch /etc/gshadow
    # Create /home/leonhardmasche/.config/cros-garcon.conf
    mkdir -p /home/leonhardmasche/.config
    echo "DisableAutomaticCrosPackageUpdates=false\nDisableAutomaticSecurityUpdates=false" > /home/leonhardmasche/.config/cros-garcon.conf
  '';
}