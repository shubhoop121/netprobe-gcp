##! Extended DHCP Logging for NetProbe (Production Grade)
##! Extracts Vendor Class, Client ID, and Param List.

module DHCP;

export {
    # Extend standard dhcp.log with Device Fingerprinting fields
    redef record Info += {
        # Option 60: Vendor Class Identifier (e.g., "MSFT 5.0", "android-dhcp-9")
        # Critical for OS Identification.
        fp_vendor_class: string &log &optional;
        
        # Option 55: Parameter Request List (e.g., [1, 3, 6, 15, ...])
        # Critical for 'fingerbank' style OS fingerprinting.
        fp_param_list: vector of count &log &optional;

        # Option 61: Client Identifier (e.g., "01:mac:addr" or DUID)
        # Critical for persistent identity if MAC Address is randomized.
        fp_client_id: string &log &optional;
    };
}

event dhcp_message(c: connection, is_orig: bool, msg: DHCP::Msg, options: DHCP::Options)
{
    # Ensure the log record exists
    if ( ! c?$dhcp ) return;

    # Extract Vendor Class (Safe string assignment)
    if ( options?$vendor_class )
        c$dhcp$fp_vendor_class = options$vendor_class;

    # Extract Parameter Request List (Safe vector assignment)
    if ( options?$param_list )
        c$dhcp$fp_param_list = options$param_list;

    # Extract Client ID (Fixing the Type Clash)
    # We use fmt("%s") to force-convert the underlying Zeek type to a standard string.
    # This prevents the "type clash" error while preserving the data.
    if ( options?$client_id )
        c$dhcp$fp_client_id = fmt("%s", options$client_id);
}