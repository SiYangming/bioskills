#!/usr/bin/env python3
import argparse
import subprocess
import sys
import os

def build_docker_command(image, volumes=None, workdir=None, cmd_parts=None):
    docker_cmd = ["docker", "run", "--rm"]
    for vol in volumes or []:
        docker_cmd.extend(["-v", vol])
    uid = os.getuid()
    gid = os.getgid()
    docker_cmd.extend(["-u", f"{uid}:{gid}"])
    if workdir:
        docker_cmd.extend(["-w", workdir])
    docker_cmd.append(image)
    parts = cmd_parts or []
    if parts and parts[0] == "--":
        parts = parts[1:]
    docker_cmd.extend(parts)
    return docker_cmd

def main():
    parser = argparse.ArgumentParser(description="Docker wrapper")
    parser.add_argument("--image", required=True)
    parser.add_argument("--volume", action="append", default=[])
    parser.add_argument("--workdir")
    parser.add_argument("--cmd", nargs=argparse.REMAINDER)
    parser.add_argument("--platform", default=os.environ.get("DOCKER_PLATFORM", "linux/amd64"))
    args = parser.parse_args()

    docker_cmd = ["docker", "run", "--rm", "--platform", args.platform]
    for vol in args.volume or []:
        docker_cmd.extend(["-v", vol])
    uid = os.getuid()
    gid = os.getgid()
    docker_cmd.extend(["-u", f"{uid}:{gid}"])
    if args.workdir:
        docker_cmd.extend(["-w", args.workdir])
    docker_cmd.append(args.image)
    parts = args.cmd or []
    if parts and parts[0] == "--":
        parts = parts[1:]
    docker_cmd.extend(parts)

    print("[DockerWrapper] Executing: " + " ".join(docker_cmd), file=sys.stderr)

    try:
        subprocess.check_call(docker_cmd)
    except subprocess.CalledProcessError as e:
        sys.exit(e.returncode)
    except Exception as e:
        print(f"Error executing docker command: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
