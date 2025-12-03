##! Extended DHCP Logging for NetProbe
##! Extracts Hostnames and Fingerprinting Options (12, 55, 60, 61, 82)

module DHCP;

export {
    # Extend standard dhcp.log
    redef record Info += {
        # Hostname (Opt 12) is standard in Zeek, no need to redef
        
        fp_vendor_class: string &log &optional;    # Option 60: "MSFT 5.0"
        fp_client_id: string &log &optional;       # Option 61: Persistent ID for Windows
        fp_param_list: vector of count &log &optional; # Option 55: OS Fingerprint
        
        # Option 82 (Relay Agent)
        fp_circuit_id: string &log &optional;
        fp_remote_id: string &log &optional;
    };
}

event dhcp_message(c: connection, is_orig: bool, msg: DHCP::Msg, options: DHCP::Options)
{
    if ( ! c?$dhcp ) return;

    # Extract Vendor Class
    if ( options?$vendor_class )
        c$dhcp$fp_vendor_class = options$vendor_class;

    # Extract Client ID (The "Hard Anchor" for Windows)
    if ( options?$client_id )
        c$dhcp$fp_client_id = options$client_id;

    # Extract Parameter Request List
    if ( options?$param_list )
        c$dhcp$fp_param_list = options$param_list;
        
    # Extract Circuit ID
    if ( options?$circuit_id )
        c$dhcp$fp_circuit_id = options$circuit_id;

    # Extract Remote ID
    if ( options?$remote_id )
        c$dhcp$fp_remote_id = options$remote_id;
}