##! Extended DHCP Logging for NetProbe
##! Extracts Hostnames and Fingerprinting Options (12, 55, 60, 82)

module DHCP;

export {
    # Extend the standard dhcp.log schema
    redef record Info += {
        host_name: string &log &optional;       # Option 12: "Davids-iPhone"
        vendor_class: string &log &optional;    # Option 60: "MSFT 5.0"
        param_list: vector of count &log &optional; # Option 55: The OS fingerprint
        circuit_id: string &log &optional;      # Option 82.1: VLAN/Switch Port
        remote_id: string &log &optional;       # Option 82.2: Original MAC
    };
}

# Event handler: Runs every time a DHCP message is seen
event dhcp_message(c: connection, is_orig: bool, msg: DHCP::Msg, options: DHCP::Options)
{
    if ( ! c?$dhcp ) return;

    # Extract Hostname
    if ( options?$host_name )
        c$dhcp$host_name = options$host_name;

    # Extract Vendor Class (OS/Hardware Type)
    if ( options?$vendor_class )
        c$dhcp$vendor_class = options$vendor_class;

    # Extract Parameter Request List (The OS "DNA")
    if ( options?$param_list )
        c$dhcp$param_list = options$param_list;
        
    # Extract Circuit ID (Location)
    if ( options?$circuit_id )
        c$dhcp$circuit_id = options$circuit_id;

    # Extract Remote ID (Original MAC)
    if ( options?$remote_id )
        c$dhcp$remote_id = options$remote_id;
}