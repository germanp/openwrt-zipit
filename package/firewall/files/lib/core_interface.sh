# Copyright (C) 2009-2010 OpenWrt.org

fw_configure_interface() {
	local iface=$1
	local action=$2
	local ifname=$3

	[ "$action" == "add" ] && {
		local status=$(uci_get_state network "$iface" up 0)
		[ "$status" == 1 ] || return 0
	}

	[ -n "$ifname" ] || ifname=$(uci_get_state network "$iface" ifname "$iface")
	[ "$ifname" == "lo" ] && return 0

	fw_callback pre interface

	fw__do_rules() {
		local action=$1
		local zone=$2
		local chain=zone_${zone}
		local ifname=$3

		local mode=$(fw_get_family_mode x $zone i)

		fw $action $mode f ${chain}_ACCEPT ACCEPT ^ { -o "$ifname" }
		fw $action $mode f ${chain}_ACCEPT ACCEPT ^ { -i "$ifname" }
		fw $action $mode f ${chain}_DROP   DROP   ^ { -o "$ifname" }
		fw $action $mode f ${chain}_DROP   DROP   ^ { -i "$ifname" }
		fw $action $mode f ${chain}_REJECT reject ^ { -o "$ifname" }
		fw $action $mode f ${chain}_REJECT reject ^ { -i "$ifname" }

		fw $action $mode n ${chain}_nat MASQUERADE ^ { -o "$ifname" }
		fw $action $mode f ${chain}_MSSFIX TCPMSS  ^ { -o "$ifname" -p tcp --tcp-flags SYN,RST SYN --clamp-mss-to-pmtu }

		fw $action $mode f input   ${chain}         $ { -i "$ifname" }
		fw $action $mode f forward ${chain}_forward $ { -i "$ifname" }
		fw $action $mode n PREROUTING ${chain}_prerouting ^ { -i "$ifname" }
		fw $action $mode r PREROUTING ${chain}_notrack    ^ { -i "$ifname" }
	}

	local old_zones old_ifname
	config_get old_zones core "${iface}_zone"
	[ -n "$old_zones" ] && {
		config_get old_ifname core "${iface}_ifname"
		for z in $old_zones; do
			fw_log info "removing $iface ($old_ifname) from zone $z"
			fw__do_rules del $z $old_ifname

			ACTION=remove ZONE="$z" INTERFACE="$iface" DEVICE="$ifname" /sbin/hotplug-call firewall
		done
		uci_revert_state firewall core "${iface}_zone"
		uci_revert_state firewall core "${iface}_ifname"
	}
	[ "$action" == del ] && return

	local new_zones
	load_zone() {
		fw_config_get_zone "$1"
		list_contains zone_network "$iface" || return

		fw_log info "adding $iface ($ifname) to zone $zone_name"
		fw__do_rules add ${zone_name} "$ifname"
		append new_zones $zone_name

		ACTION=add ZONE="$zone_name" INTERFACE="$iface" DEVICE="$ifname" /sbin/hotplug-call firewall
	}
	config_foreach load_zone zone

	uci_set_state firewall core "${iface}_zone" "$new_zones"
	uci_set_state firewall core "${iface}_ifname" "$ifname"

	fw_sysctl_interface $ifname

	fw_callback post interface
}

fw_sysctl_interface() {
	local ifname=$1
	{
		sysctl -w net.ipv4.conf.${ifname}.accept_redirects=$FW_ACCEPT_REDIRECTS
		sysctl -w net.ipv6.conf.${ifname}.accept_redirects=$FW_ACCEPT_REDIRECTS
		sysctl -w net.ipv4.conf.${ifname}.accept_source_route=$FW_ACCEPT_SRC_ROUTE
		sysctl -w net.ipv6.conf.${ifname}.accept_source_route=$FW_ACCEPT_SRC_ROUTE
	} >/dev/null 2>/dev/null
}
