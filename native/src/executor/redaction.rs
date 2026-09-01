const URL_MARKER: &[u8] = b"://";
const SENSITIVE_KEYS: [&[u8]; 6] = [
    b"access_token=",
    b"refresh_token=",
    b"password=",
    b"passwd=",
    b"secret=",
    b"token=",
];

pub fn redact_remote(remote: &str) -> String {
    redact_bytes(remote.as_bytes())
}

pub fn redact_bytes(input: &[u8]) -> String {
    let mut redacted = input.to_vec();
    redact_url_userinfo(&mut redacted);
    redact_sensitive_values(&mut redacted);
    String::from_utf8_lossy(&redacted).into_owned()
}

fn redact_url_userinfo(value: &mut Vec<u8>) {
    let mut search_from = 0;
    while let Some(marker_offset) = find_bytes(value, URL_MARKER, search_from) {
        let authority_start = marker_offset + URL_MARKER.len();
        let authority_end = value[authority_start..]
            .iter()
            .position(|byte| {
                matches!(
                    byte,
                    b'/' | b'?' | b'#' | b' ' | b'\t' | b'\r' | b'\n' | b'\'' | b'"'
                )
            })
            .map_or(value.len(), |offset| authority_start + offset);
        let userinfo_end = value[authority_start..authority_end]
            .iter()
            .rposition(|byte| *byte == b'@')
            .map(|offset| authority_start + offset + 1);

        if let Some(userinfo_end) = userinfo_end {
            value.splice(authority_start..userinfo_end, b"***@".iter().copied());
            search_from = authority_start + 4;
        } else {
            search_from = authority_end;
        }
    }
}

fn redact_sensitive_values(value: &mut Vec<u8>) {
    for key in SENSITIVE_KEYS {
        let mut search_from = 0;
        while let Some(key_offset) = find_ascii_case_insensitive(value, key, search_from) {
            let value_start = key_offset + key.len();
            let value_end = value[value_start..]
                .iter()
                .position(|byte| matches!(byte, b' ' | b'\t' | b'\r' | b'\n' | b'&' | b'\'' | b'"'))
                .map_or(value.len(), |offset| value_start + offset);
            value.splice(value_start..value_end, b"***".iter().copied());
            search_from = value_start + 3;
        }
    }
}

fn find_bytes(value: &[u8], needle: &[u8], search_from: usize) -> Option<usize> {
    value[search_from..]
        .windows(needle.len())
        .position(|window| window == needle)
        .map(|offset| search_from + offset)
}

fn find_ascii_case_insensitive(value: &[u8], needle: &[u8], search_from: usize) -> Option<usize> {
    value[search_from..]
        .windows(needle.len())
        .position(|window| window.eq_ignore_ascii_case(needle))
        .map(|offset| search_from + offset)
}
