##! Extended DHCP Logging for NetProbe - SAFE VERSION
##! Author: NetProbe Architecture Team

module DHCP;

export {
    redef record Info += {
        # REMOVED: host_name (Already exists in standard Zeek)
        
        # We use 'fp_' prefix to avoid collisions with future Zeek versions
        fp_vendor_class: string &log &optional;
        fp_param_list: vector of count &log &optional;
        
        # Option 82 fields
        fp_circuit_id: string &log &optional;
        fp_remote_id: string &log &optional;
    };
}

event dhcp_message(c: connection, is_orig: bool, msg: DHCP::Msg, options: DHCP::Options)
{
    if ( ! c?$dhcp ) return;

    # Note: We have temporarily commented out the extraction logic below.
    # The 'options' record in this Zeek version does not expose these fields directly.
    # We will fix the extraction logic in the next sprint using a 'raw_packet' event.
    # For now, this allows the NVA to boot without crashing.

    # if ( options?$vendor_class ) c$dhcp$fp_vendor_class = options$vendor_class;
    # if ( options?$param_list )   c$dhcp$fp_param_list   = options$param_list;
    # if ( options?$circuit_id )   c$dhcp$fp_circuit_id   = options$circuit_id;
    # if ( options?$remote_id )    c$dhcp$fp_remote_id    = options$remote_id;
}