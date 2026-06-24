#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional, Tuple

__version__ = '1.0.0'

DEFAULT_SIEM_CONFIG = '/Library/Application Support/airdrop-monitor/siem.conf'

TS_RE = re.compile(r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+[+-]\d{4})')
TRANSFER_ID_RE = re.compile(r'transferID: ([A-F0-9]{8})')
TRANSFER_STATE_ID_RE = re.compile(r'\{id: ([A-F0-9]{8})[,}]')
AIRDROP_TAG_ID_RE = re.compile(r'\[com\.apple\.sharing:AirDrop\.([A-F0-9]{8})\]')
UUID_RE = re.compile(r'([A-F0-9-]{36})')
FILE_URL_RE = re.compile(r'file://[^\]\)\}\],\s]+')
QUOTED_FILENAME_RE = re.compile(r'[“\"]([^”\"]+)[”\"]')
ASK_SENDER_RE = re.compile(r'would like to share [“\"]([^”\"]+)[”\"]')
RECEIVED_FROM_RE = re.compile(r'Received [“\”]([^”\”]+)[“\”] from ([^)}\]]+)')
PROMPT_FROM_RE = re.compile(r'prompt: (.+?) would like to share [“\"]([^”\"]+)[”\"]')
CONTACT_RE = re.compile(r'contact:([A-F0-9-]{36})')
SEND_ASK_END_RE = re.compile(r'ASK response Nm "([^"]+)"(?:, Md ([^,\}]+))?')

IMPORTANT_SUBSTRINGS = [
    'Received ASK request',
    'User accepted AirDrop notification',
    'Received UPLOAD request',
    'AirDrop destination set to ',
    'Created ',
    'Start progress for url:',
    'Decompression succeeded',
    'Importing START',
    'Importing END',
    'Sending ASK request',
    'Adding file items',
    'Sending UPLOAD request',
    'Passing real URLS to zipper',
    'Received ASK response',
    'Send StateMachine ASK END',
    'Received UPLOAD response',
    'Send StateMachine END',
    'state: .completedSuccessfully',
    'state: .transferring(completed(file://',
]


def iso_now_local() -> str:
    return dt.datetime.now().astimezone().isoformat()


def parse_ts(line: str) -> Optional[str]:
    m = TS_RE.match(line)
    return m.group(1) if m else None


def normalize_file_url(url: str) -> str:
    return url.rstrip(']}),')


def file_url_to_path(url: str) -> str:
    if url.startswith('file://'):
        return url[7:]
    return url


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def read_state(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def write_state(path: Path, state: Dict[str, str]) -> None:
    path.write_text(json.dumps(state, indent=2, sort_keys=True))


def extract_transfer_id(line: str) -> Optional[str]:
    for regex in (TRANSFER_ID_RE, TRANSFER_STATE_ID_RE, AIRDROP_TAG_ID_RE):
        m = regex.search(line)
        if m:
            return m.group(1)
    return None


def extract_urls(line: str) -> List[str]:
    urls = [normalize_file_url(u) for u in FILE_URL_RE.findall(line)]
    seen = []
    for u in urls:
        if u not in seen:
            seen.append(u)
    return seen


def choose_or_create_transfer(transfers: Dict[str, dict], direction: str, line: str) -> dict:
    transfer_id = extract_transfer_id(line)
    if transfer_id:
        return transfers.setdefault(transfer_id, new_transfer(transfer_id, direction))

    candidates = [t for t in transfers.values() if t['direction'] == direction and t.get('status') not in ('completed', 'completed_successfully', 'failed')]
    if candidates:
        candidates.sort(key=lambda x: x.get('last_seen') or '')
        return candidates[-1]

    synthetic_id = f"synthetic-{direction}-{len(transfers)+1}"
    transfer = new_transfer(synthetic_id, direction)
    transfers[synthetic_id] = transfer
    return transfer


def new_transfer(transfer_id: str, direction: str) -> dict:
    return {
        'transfer_id': transfer_id,
        'direction': direction,
        'first_seen': None,
        'last_seen': None,
        'sender_name': None,
        'recipient_name': None,
        'contact_id': None,
        'device_name': None,
        'filename': None,
        'source_path': None,
        'destination_path': None,
        'destination_dir': None,
        'status': None,
        'accepted': False,
        'bytes_total': None,
        'events': [],
        'important_lines': [],
    }


def add_event(transfer: dict, ts: Optional[str], event_type: str, line: str) -> None:
    transfer['events'].append({'ts': ts, 'event': event_type, 'line': line})
    transfer['last_seen'] = ts or transfer['last_seen']
    if not transfer['first_seen']:
        transfer['first_seen'] = ts
    if any(s in line for s in IMPORTANT_SUBSTRINGS):
        transfer['important_lines'].append({'ts': ts, 'line': line})


def set_filename_from_path(transfer: dict, path: str, field: str) -> None:
    if path:
        transfer[field] = path
        transfer['filename'] = os.path.basename(path)


def parse_line(line: str, transfers: Dict[str, dict]) -> None:
    if 'sharingd:' not in line or 'AirDrop' not in line:
        return

    ts = parse_ts(line)
    direction = 'incoming'
    if ('SDAirDropSendService' in line or
        'Starting send to ' in line or
        'Send StateMachine' in line or
        'Sending UPLOAD request' in line or
        'Adding file items' in line or
        'Passing real URLS to zipper' in line):
        direction = 'outgoing'

    transfer = choose_or_create_transfer(transfers, direction, line)

    # Generic URL extraction.
    urls = extract_urls(line)
    if urls:
        path = file_url_to_path(urls[0])
        if direction == 'incoming' and ('Start progress for url:' in line or 'Decompression succeeded' in line or 'Importing START' in line or 'Importing END' in line or 'Set quarantine state on url' in line):
            set_filename_from_path(transfer, path, 'destination_path')
        elif direction == 'outgoing' and ('Adding file items' in line or 'Sending UPLOAD request' in line or 'Passing real URLS to zipper' in line):
            set_filename_from_path(transfer, path, 'source_path')

    # Incoming markers.
    if 'AirDrop destination set to ' in line:
        transfer['destination_dir'] = line.split('AirDrop destination set to ', 1)[1].strip()
        add_event(transfer, ts, 'destination_dir', line)
        return

    if 'Received ASK request' in line:
        transfer['status'] = 'ask_received'
        add_event(transfer, ts, 'ask_received', line)
        return

    if 'User accepted AirDrop notification' in line:
        transfer['accepted'] = True
        transfer['status'] = 'accepted'
        add_event(transfer, ts, 'accepted', line)
        return

    if 'state: .waitingForAskResponse(prompt:' in line:
        m = PROMPT_FROM_RE.search(line)
        if m:
            transfer['sender_name'] = m.group(1)
            transfer['filename'] = m.group(2)
        transfer['status'] = 'waiting_for_accept'
        add_event(transfer, ts, 'waiting_for_accept', line)
        return

    if 'Received UPLOAD request ' in line:
        m = re.search(r'Received UPLOAD request (\d+)', line)
        if m:
            transfer['bytes_total'] = int(m.group(1))
        transfer['status'] = 'upload_started'
        add_event(transfer, ts, 'upload_started', line)
        return

    if 'Created ' in line and ' placeholder files' in line:
        add_event(transfer, ts, 'placeholder_created', line)
        return

    if 'Start progress for url:' in line:
        add_event(transfer, ts, 'file_progress_started', line)
        return

    if 'Decompression succeeded' in line:
        transfer['status'] = 'decompressed'
        add_event(transfer, ts, 'decompressed', line)
        return

    if 'Importing START' in line:
        transfer['status'] = 'importing'
        add_event(transfer, ts, 'importing_start', line)
        return

    if 'Importing END' in line:
        transfer['status'] = 'imported'
        add_event(transfer, ts, 'importing_end', line)
        return

    if 'state: .waitingForOpenResponse(prompt: Received ' in line:
        m = RECEIVED_FROM_RE.search(line)
        if m:
            transfer['filename'] = m.group(1)
            transfer['sender_name'] = m.group(2)
        add_event(transfer, ts, 'open_prompt', line)
        return

    if 'state: .completedSuccessfully' in line and direction == 'incoming':
        transfer['status'] = 'completed_successfully'
        add_event(transfer, ts, 'completed_successfully', line)
        return

    # Outgoing markers.
    if 'Starting send to [' in line:
        transfer['status'] = 'send_started'
        add_event(transfer, ts, 'send_started', line)
        return

    if 'Adding file items (count=' in line:
        transfer['status'] = 'files_added'
        add_event(transfer, ts, 'files_added', line)
        return

    if 'Sending ASK request' in line:
        transfer['status'] = 'ask_sent'
        add_event(transfer, ts, 'ask_sent', line)
        return

    if 'Received ASK response' in line:
        transfer['status'] = 'ask_accepted'
        add_event(transfer, ts, 'ask_accepted', line)
        return

    if 'Send StateMachine ASK END' in line:
        m = SEND_ASK_END_RE.search(line)
        if m:
            transfer['recipient_name'] = m.group(1)
            md = (m.group(2) or '').strip()
            if md and md != 'nil':
                transfer['device_name'] = md
        add_event(transfer, ts, 'ask_end', line)
        return

    if 'Sending UPLOAD request' in line:
        transfer['status'] = 'upload_started'
        add_event(transfer, ts, 'upload_started', line)
        return

    if 'Passing real URLS to zipper' in line:
        add_event(transfer, ts, 'zipping_source', line)
        return

    if 'Zipper Update: (' in line and direction == 'outgoing':
        quoted = QUOTED_FILENAME_RE.search(line)
        if quoted:
            transfer['filename'] = os.path.basename(quoted.group(1).replace(' -- file:///', ''))
        add_event(transfer, ts, 'zipper_listing', line)
        return

    if 'Received UPLOAD response' in line:
        transfer['status'] = 'upload_acknowledged'
        add_event(transfer, ts, 'upload_acknowledged', line)
        return

    if 'state: .transferring(completed(file://' in line and direction == 'outgoing':
        transfer['status'] = 'upload_completed'
        add_event(transfer, ts, 'upload_completed', line)
        return

    if 'state: .completedSuccessfully' in line and direction == 'outgoing':
        transfer['status'] = 'completed_successfully'
        add_event(transfer, ts, 'completed_successfully', line)
        return

    # Enrichments.
    if 'Found paired contact for contactID:' in line or 'Successfully verified identity and found contactID:' in line:
        m = UUID_RE.search(line)
        if m:
            transfer['contact_id'] = m.group(1)
        add_event(transfer, ts, 'contact_enriched', line)
        return

    if 'Message id:' in line and 'ASK request ID' in line:
        sender_match = re.search(r'Sender ([A-F0-9-]{36}), Nm "([^"]+)"(?:, Md ([^,]+))?', line)
        if sender_match and direction == 'incoming':
            transfer['device_name'] = sender_match.group(2)
            if sender_match.group(3):
                transfer['recipient_name'] = sender_match.group(3)
        add_event(transfer, ts, 'ask_message', line)
        return

    add_event(transfer, ts, 'other', line)


def is_meaningful_transfer(t: dict) -> bool:
    if t.get('filename') or t.get('source_path') or t.get('destination_path'):
        return True
    if t.get('destination_dir') and t.get('accepted'):
        return True
    if not t.get('transfer_id', '').startswith('synthetic-'):
        return True
    return False


def summarize(transfers: Dict[str, dict]) -> dict:
    items = [t for t in transfers.values() if is_meaningful_transfer(t)]
    incoming = [t for t in items if t['direction'] == 'incoming']
    outgoing = [t for t in items if t['direction'] == 'outgoing']
    return {
        'generated_at': iso_now_local(),
        'tool_version': __version__,
        'total_transfers': len(items),
        'incoming_transfers': len(incoming),
        'outgoing_transfers': len(outgoing),
        'completed_successfully': sum(1 for t in items if t.get('status') == 'completed_successfully'),
        'transfers': items,
    }


def filter_raw_lines(lines: List[str]) -> List[str]:
    out = []
    for line in lines:
        if 'sharingd:' not in line:
            continue
        if 'com.apple.sharing:AirDrop' not in line:
            continue
        out.append(line.rstrip('\n'))
    return out


def collect_live_logs(start: str, end: str, include_info: bool = True, include_debug: bool = False) -> List[str]:
    cmd = ['/usr/bin/log', 'show', '--start', start, '--end', end]
    if include_info:
        cmd.append('--info')
    if include_debug:
        cmd.append('--debug')
    cmd += ['--predicate', 'process == "sharingd" AND subsystem == "com.apple.sharing" AND (category CONTAINS "AirDrop")']
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or 'log show failed')
    return result.stdout.splitlines()


def process_lines(raw_lines: List[str]) -> Tuple[List[str], Dict[str, dict], dict]:
    filtered = filter_raw_lines(raw_lines)
    transfers: Dict[str, dict] = {}
    for line in filtered:
        parse_line(line, transfers)
    summary = summarize(transfers)
    return filtered, transfers, summary


def write_outputs(base_dir: Path, filtered_lines: List[str], summary: dict) -> Optional[Dict[str, str]]:
    if summary['total_transfers'] == 0:
        return None

    ts = dt.datetime.now().astimezone().strftime('%Y%m%d-%H%M%S')
    raw_path = base_dir / f'raw-{ts}.log'
    jsonl_path = base_dir / f'parsed-{ts}.jsonl'
    summary_path = base_dir / f'summary-{ts}.json'

    raw_path.write_text('\n'.join(filtered_lines) + ('\n' if filtered_lines else ''))
    with jsonl_path.open('w') as f:
        for item in summary['transfers']:
            f.write(json.dumps(item, sort_keys=True) + '\n')
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True))

    latest = {
        'raw_log': str(raw_path),
        'parsed_jsonl': str(jsonl_path),
        'summary_json': str(summary_path),
    }
    (base_dir / 'latest.json').write_text(json.dumps(latest, indent=2, sort_keys=True))
    return latest


class _KeepMethodRedirectHandler(urllib.request.HTTPRedirectHandler):
    # urllib downgrades POST→GET on 301/302 redirects; this preserves the original method.
    def redirect_request(self, req, _fp, _code, _msg, _headers, newurl):
        return urllib.request.Request(
            newurl,
            data=req.data,
            headers={k: v for k, v in req.header_items()},
            method=req.get_method(),
        )


def load_siem_config(path: Path) -> Tuple[Optional[str], Optional[str]]:
    if not path.is_file():
        return None, None
    try:
        st = path.stat()
    except OSError as e:
        print(f'WARNING: cannot stat SIEM config {path}: {e}', file=sys.stderr)
        return None, None
    if st.st_uid != 0:
        print(f'WARNING: refusing to read {path}: not owned by root', file=sys.stderr)
        return None, None
    if st.st_mode & 0o077:
        print(f'WARNING: refusing to read {path}: permissions broader than 0600', file=sys.stderr)
        return None, None
    url, key = None, None
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        k, v = k.strip(), v.strip()
        if k == 'SIEM_HEC_URL':
            url = v
        elif k == 'SIEM_API_KEY':
            key = v
    return url, key


def _to_hec_event(transfer: dict) -> str:
    event = {k: v for k, v in transfer.items() if k != 'events'}
    event['tool_version'] = __version__
    return json.dumps(event, sort_keys=True)


def send_to_hec(lines: List[str], hec_url: str, api_key: str) -> None:
    payload = '\n'.join(lines).encode('utf-8')
    req = urllib.request.Request(
        hec_url,
        data=payload,
        method='POST',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'text/plain',
        },
    )
    opener = urllib.request.build_opener(_KeepMethodRedirectHandler)
    try:
        with opener.open(req) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'HEC ingest failed: HTTP {e.code} {e.reason}') from e
    if status not in (200, 204):
        raise RuntimeError(f'HEC ingest returned unexpected status {status}')


def process_file_mode(input_paths: List[Path], base_dir: Path, stdout: bool,
                      siem_hec_url: Optional[str] = None,
                      siem_api_key: Optional[str] = None) -> int:
    combined_lines: List[str] = []
    for path in input_paths:
        combined_lines.extend(path.read_text(errors='replace').splitlines())
    filtered, _transfers, summary = process_lines(combined_lines)
    latest = write_outputs(base_dir, filtered, summary)
    if siem_hec_url and siem_api_key:
        hec_lines = [_to_hec_event(t) for t in summary['transfers']]
        if hec_lines:
            send_to_hec(hec_lines, siem_hec_url, siem_api_key)
    if stdout:
        print(json.dumps({'summary': summary, 'files': latest}, indent=2, sort_keys=True))
    return 0


def process_live_mode(base_dir: Path, interval_seconds: int, include_info: bool, include_debug: bool, stdout: bool, dry_run: bool,
                      siem_hec_url: Optional[str] = None,
                      siem_api_key: Optional[str] = None) -> int:
    state_path = base_dir / 'state.json'
    state = read_state(state_path)
    end_dt = dt.datetime.now().astimezone()

    if state.get('last_end'):
        start_str = state['last_end']
    else:
        start_dt = end_dt - dt.timedelta(seconds=interval_seconds)
        start_str = start_dt.strftime('%Y-%m-%d %H:%M:%S')

    end_str = end_dt.strftime('%Y-%m-%d %H:%M:%S')
    raw_lines = collect_live_logs(start_str, end_str, include_info=include_info, include_debug=include_debug)
    filtered, _transfers, summary = process_lines(raw_lines)
    latest = write_outputs(base_dir, filtered, summary)

    if siem_hec_url and siem_api_key:
        hec_lines = [_to_hec_event(t) for t in summary['transfers']]
        if hec_lines:
            send_to_hec(hec_lines, siem_hec_url, siem_api_key)

    if not dry_run:
        write_state(state_path, {'last_end': end_str, 'last_run': iso_now_local()})

    if stdout:
        print(json.dumps({
            'start': start_str,
            'end': end_str,
            'summary': summary,
            'files': latest,
            'dry_run': dry_run,
        }, indent=2, sort_keys=True))
    return 0


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description='Collect and parse macOS AirDrop sharingd unified logs.')
    p.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    p.add_argument('--base-dir', default='/var/log/airdrop-monitor', help='Output directory for raw, parsed, and summary files.')
    p.add_argument('--interval-seconds', type=int, default=900, help='Fallback lookback window when no state file exists.')
    p.add_argument('--include-info', action='store_true', help='Include info-level logs when querying unified logs.')
    p.add_argument('--include-debug', action='store_true', help='Include debug-level logs when querying unified logs.')
    p.add_argument('--stdout', action='store_true', help='Print summary JSON to stdout.')
    p.add_argument('--dry-run', action='store_true', help='Do not update the state file.')
    p.add_argument('--from-file', action='append', default=[], help='Parse one or more exported log files instead of calling log show.')
    p.add_argument('--siem-hec-url', default=os.environ.get('CROWDSTRIKE_HEC_URL'), help='Full CrowdStrike NG-SIEM HEC endpoint URL (env: CROWDSTRIKE_HEC_URL). Overrides --siem-config-file when set.')
    p.add_argument('--siem-api-key', default=os.environ.get('CROWDSTRIKE_API_KEY'), help='CrowdStrike API key for HEC ingest (env: CROWDSTRIKE_API_KEY). Overrides --siem-config-file when set.')
    p.add_argument('--siem-config-file', default=DEFAULT_SIEM_CONFIG, help=f'KEY=VALUE file containing SIEM_HEC_URL and SIEM_API_KEY (default: {DEFAULT_SIEM_CONFIG}). Must be root-owned mode 0600.')
    return p


def main() -> int:
    args = build_arg_parser().parse_args()

    if not args.from_file and os.geteuid() != 0:
        print('ERROR: live mode requires root. Re-run with sudo.', file=sys.stderr)
        return 1

    base_dir = Path(args.base_dir)
    ensure_dir(base_dir)

    siem_url = args.siem_hec_url
    siem_key = args.siem_api_key
    if not (siem_url and siem_key) and args.siem_config_file:
        cfg_url, cfg_key = load_siem_config(Path(args.siem_config_file))
        siem_url = siem_url or cfg_url
        siem_key = siem_key or cfg_key

    siem_kwargs = dict(
        siem_hec_url=siem_url,
        siem_api_key=siem_key,
    )

    if args.from_file:
        input_paths = [Path(p) for p in args.from_file]
        return process_file_mode(input_paths, base_dir, args.stdout, **siem_kwargs)

    return process_live_mode(
        base_dir=base_dir,
        interval_seconds=args.interval_seconds,
        include_info=args.include_info,
        include_debug=args.include_debug,
        stdout=args.stdout,
        dry_run=args.dry_run,
        **siem_kwargs,
    )


if __name__ == '__main__':
    sys.exit(main())
