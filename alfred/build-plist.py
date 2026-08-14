#!/usr/bin/env python3
"""Generate alfred/info.plist. Run: python3 alfred/build-plist.py"""

import plistlib
import pathlib

BUNDLE = "com.markbiek.ct-alfred"
SHIM = 'export PATH="$HOME/.local/bin:$PATH"; exec ct-alfred {} "$1"'


def script_filter(uid, keyword, subcommand, title, alfred_filters):
    return {
        "uid": uid,
        "type": "alfred.workflow.input.scriptfilter",
        "version": 3,
        "config": {
            "alfredfiltersresults": alfred_filters,
            "alfredfiltersresultsmatchmode": 0,
            "argumenttreatemptyqueryasnil": True,
            "argumenttrimmode": 0,
            "argumenttype": 1,          # optional argument
            "escaping": 102,
            "keyword": keyword,
            "queuedelaycustom": 3,
            "queuedelayimmediatelyinitially": True,
            "queuedelaymode": 0,
            "queuemode": 1,
            "runningsubtext": "Working...",
            "script": SHIM.format(subcommand),
            "scriptargtype": 1,         # argv
            "scriptfile": "",
            "subtext": "",
            "title": title,
            "type": 0,                  # bash
            "withspace": True,
        },
    }


def run_script(uid, subcommand):
    return {
        "uid": uid,
        "type": "alfred.workflow.action.script",
        "version": 2,
        "config": {
            "concurrently": False,
            "escaping": 102,
            "script": SHIM.format(subcommand),
            "scriptargtype": 1,
            "scriptfile": "",
            "type": 0,
        },
    }


def notification(uid, title):
    return {
        "uid": uid,
        "type": "alfred.workflow.output.notification",
        "version": 1,
        "config": {"lastpathcomponent": False, "onlyshowifquerypopulated": False,
                   "removeextension": False, "text": "{query}", "title": title},
    }


def set_query(uid):
    """Reopen Alfred with the ctn keyword and the picked issue prefilled."""
    return {
        "uid": uid,
        "type": "alfred.workflow.action.script",
        "version": 2,
        "config": {
            "concurrently": False,
            "escaping": 102,
            "script": (
                'osascript -e "tell application \\"Alfred 5\\" '
                'to search \\"ctn $1\\""'
            ),
            "scriptargtype": 1,
            "scriptfile": "",
            "type": 0,
        },
    }


def link(src, dst, modifier=0):
    return {"destinationuid": dst, "modifiers": modifier,
            "modifiersubtext": "", "vitoclose": False}


UIDS = {
    "sf_switch": "10000000-0000-0000-0000-000000000001",
    "sf_new": "10000000-0000-0000-0000-000000000002",
    "sf_linear": "10000000-0000-0000-0000-000000000003",
    "do_switch": "20000000-0000-0000-0000-000000000001",
    "do_finish": "20000000-0000-0000-0000-000000000002",
    "do_new": "20000000-0000-0000-0000-000000000003",
    "set_query": "20000000-0000-0000-0000-000000000004",
    "notify": "30000000-0000-0000-0000-000000000001",
}

objects = [
    script_filter(UIDS["sf_switch"], "ct", "switch-list",
                  "Switch to a ct task", True),
    script_filter(UIDS["sf_new"], "ctn", "new-list",
                  "Create a ct task", False),
    script_filter(UIDS["sf_linear"], "ctl", "linear-list",
                  "Start a ct task from a Linear issue", True),
    run_script(UIDS["do_switch"], "do-switch"),
    run_script(UIDS["do_finish"], "do-finish"),
    run_script(UIDS["do_new"], "do-new"),
    set_query(UIDS["set_query"]),
    notification(UIDS["notify"], "ct"),
]

# Cmd (modifier 1048576) on the switch list finishes instead of switching.
connections = {
    UIDS["sf_switch"]: [link(None, UIDS["do_switch"], 0),
                        link(None, UIDS["do_finish"], 1048576)],
    UIDS["sf_new"]: [link(None, UIDS["do_new"])],
    UIDS["sf_linear"]: [link(None, UIDS["set_query"])],
    UIDS["do_switch"]: [link(None, UIDS["notify"])],
    UIDS["do_finish"]: [link(None, UIDS["notify"])],
    UIDS["do_new"]: [link(None, UIDS["notify"])],
}

plist = {
    "bundleid": BUNDLE,
    "connections": connections,
    "createdby": "Mark Biek",
    "description": "Switch, create, and finish ct tasks",
    "disabled": False,
    "name": "ct",
    "objects": objects,
    "readme": (
        "Requires ct on PATH. Install it with the repo's install.sh.\n\n"
        "  ct   switch to a task; cmd-enter finishes it\n"
        "  ctn  create a task: pick a repo, then type a name\n"
        "  ctl  start from an assigned Linear issue\n"
    ),
    "uidata": {uid: {"xpos": 100 + 200 * (i % 3), "ypos": 100 + 120 * (i // 3)}
               for i, uid in enumerate(UIDS.values())},
    "variablesdontexport": [],
    "version": "1.0",
    "webaddress": "",
}

out = pathlib.Path(__file__).parent / "info.plist"
with out.open("wb") as fh:
    plistlib.dump(plist, fh)
print(f"wrote {out}")
