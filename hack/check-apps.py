#!/usr/bin/env python3
"""Policy checks for the Argo CD Applications in apps/, run in CI.

Argo CD enforces AppProjects only when it syncs, i.e. after the merge. These
checks fail the pull request instead:
  - every Application is in a project defined in apps/projects.yaml
    ("default" is reserved for the root app);
  - its repos and destination namespace are allowed by that project;
  - upstream Helm charts are pinned to an exact version;
  - automated sync has a retry policy.
"""

import glob
import re
import sys

import yaml

EXACT_VERSION = re.compile(r"^v?\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$")


def load(paths):
    for path in paths:
        with open(path) as f:
            for doc in yaml.safe_load_all(f):
                if doc:
                    yield path, doc


def check(app_paths, project_paths):
    projects = {d["metadata"]["name"]: d["spec"] for _, d in load(project_paths) if d["kind"] == "AppProject"}
    errors = []
    for path, app in load(app_paths):
        if app.get("kind") != "Application":
            continue
        name, spec = app["metadata"]["name"], app["spec"]

        def err(msg, name=name, path=path):
            errors.append(f"{path}: {name}: {msg}")

        project = spec.get("project", "default")
        if project == "default":
            err('uses the "default" project, which is reserved for the root app')
            continue
        if project not in projects:
            err(f'project "{project}" is not defined in apps/projects.yaml')
            continue
        proj = projects[project]

        sources = spec.get("sources") or [spec.get("source", {})]
        for src in sources:
            repo = src.get("repoURL", "")
            if repo not in proj.get("sourceRepos", []) and "*" not in proj.get("sourceRepos", []):
                err(f'repo {repo} is not in project "{project}" sourceRepos')
            if "chart" in src and not EXACT_VERSION.match(str(src.get("targetRevision", ""))):
                err(f'chart {src["chart"]} must be pinned to an exact version, got "{src.get("targetRevision")}"')

        ns = spec.get("destination", {}).get("namespace", "")
        allowed = {d.get("namespace") for d in proj.get("destinations", [])}
        if ns not in allowed and "*" not in allowed:
            err(f'namespace "{ns}" is not a destination of project "{project}"')

        sync = spec.get("syncPolicy", {})
        if "automated" in sync and "retry" not in sync:
            err("automated sync without a retry policy")
    return errors


def main():
    errors = check(sorted(glob.glob("apps/*.yaml")), ["apps/projects.yaml"])
    for e in errors:
        print(f"::error::{e}")
    print(f"{len(errors)} problem(s)" if errors else "all Applications pass the policy checks")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
