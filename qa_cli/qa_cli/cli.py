import re
import click
import paramiko
import socket
import time
from typing import Optional
import os
from pathlib import Path
# Stage-0 checks temporarily disabled – we only need SSH right now.

def validate_truffle_id(ctx, param, value: str) -> str:
    """Validate the truffle ID format (truffle-XXXX where X is a digit)."""
    if not value:
        raise click.BadParameter("Truffle ID is required")
    
    pattern = r'^truffle-\d{4}$'
    if not re.match(pattern, value):
        raise click.BadParameter("Truffle ID must be in format 'truffle-XXXX' where X is a digit")
    return value

# def create_truffle_directory(truffle_id: str) -> tuple[bool, str]:
#     """Create a directory for the truffle if it doesn't exist."""
#     base_dir = Path(os.path.expanduser("/home/truffle/abd_work/trufflw_QA"))
#     truffle_dir = base_dir / truffle_id
    
#     try:
#         # Create base directory if it doesn't exist (create parents just in case)
#         base_dir.mkdir(parents=True, exist_ok=True)
        
#         # Check if truffle directory already exists
#         if truffle_dir.exists():
#             return True, f"Directory {truffle_id} already exists"
        
#         # Create truffle directory (again with parents for robustness)
#         truffle_dir.mkdir(parents=True, exist_ok=True)
#         return True, f"Created directory for {truffle_id}"
#     except Exception as e:
#         return False, f"Failed to create directory: {str(e)}"

# ---------------------------------------------------------------------------
# SSH helpers
# ---------------------------------------------------------------------------

def run_remote_command(
    hostname: str,
    command: str,
    sudo_password: str = "runescape",
    *,
    allow_disconnect: bool = False,
) -> tuple[bool, str]:
    """Execute *command* on *hostname* using paramiko with *live* streaming.

    The remote output is echoed to the local terminal in real-time. If the
    connection drops unexpectedly (e.g. because the remote host reboots) *and*
    ``allow_disconnect`` is *True*, the function returns ``(True, collected)`` so
    the caller can proceed to wait for the machine to come back online.
    """

    collected: list[str] = []
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(hostname=hostname, username="truffle", password=sudo_password, timeout=10)

        # Allocate a PTY so that sudo behaves exactly as when run manually
        stdin, stdout, stderr = client.exec_command(command, get_pty=True)

        # If the command is run via sudo (-S flag), feed the password once
        if command.strip().startswith("sudo") and "-S" in command:
            stdin.write(f"{sudo_password}\n")
            stdin.flush()

        chan = stdout.channel

        while not chan.exit_status_ready():
            # stdout
            while chan.recv_ready():
                data = chan.recv(1024)
                if not data:
                    break
                text = data.decode(errors="replace")
                collected.append(text)
                click.echo(text, nl=False)
                click.get_text_stream('stdout').flush()

            # stderr
            while chan.recv_stderr_ready():
                data = chan.recv_stderr(1024)
                if not data:
                    break
                text = data.decode(errors="replace")
                collected.append(text)
                click.echo(text, nl=False)
                click.get_text_stream('stdout').flush()

            # Keep the loop cooperative
            time.sleep(0.1)

        # collect any remaining data after command finished
        remaining_out = stdout.read().decode(errors="replace")
        remaining_err = stderr.read().decode(errors="replace")
        if remaining_out:
            collected.append(remaining_out)
            click.echo(remaining_out, nl=False)
            click.get_text_stream('stdout').flush()
        if remaining_err:
            collected.append(remaining_err)
            click.echo(remaining_err, nl=False)
            click.get_text_stream('stdout').flush()

        exit_status = chan.recv_exit_status()
        client.close()

        return exit_status == 0, "".join(collected)

    except Exception as exc:
        # If disconnects are acceptable (e.g. remote reboot), treat them as OK
        if allow_disconnect:
            click.echo(f"\n⚠️  Connection lost: {exc}\n")
            return True, "".join(collected)

        return False, f"Exception: {exc}\n{''.join(collected)}"

def wait_for_ssh(hostname: str, timeout: int = 300, interval: int = 5) -> bool:
    """Block until *hostname* is reachable on port 22 or *timeout* (seconds) elapses.

    Returns True if the host became reachable, False otherwise.  A dot is
    printed every *interval* seconds as a heartbeat so the user knows the
    process is still alive.
    """
    click.echo("\n🔄 Waiting for SSH service on {} …".format(hostname))
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            with socket.create_connection((hostname, 22), timeout=3):
                click.echo("  ✅ Host reachable!\n")
                return True
        except OSError:
            click.echo(".", nl=False)
            click.get_text_stream('stdout').flush()  # ensure dot is shown immediately
            time.sleep(interval)

    click.echo("\n❌ Timed out waiting for SSH to come back.")
    return False

@click.group()
def cli():
    """QA CLI tool for interacting with truffle machines."""
    pass

@cli.command()
@click.option(
    '--truffle-id',
    prompt='Enter the truffle ID (format: truffle-XXXX)',
    callback=validate_truffle_id,
    help='The ID of the truffle machine to connect to'
)
def qa(truffle_id: str):
    """Start the QA process with the specified truffle machine."""

    # -------------------------------------------------------------------
    # 1. Local preparation – create directory
    # -------------------------------------------------------------------
    # success, message = create_truffle_directory(truffle_id)
    # if not success:
    #     click.echo(click.style(f"Error: {message}", fg="red"))
    #     raise click.Abort()
    # click.echo(click.style(message, fg="green"))

    # -------------------------------------------------------------------
    # 2. Remote stages execution
    # -------------------------------------------------------------------
    hostname = f"{truffle_id}.local"

    # Stage 0
    if click.confirm("Would you like to run stage 0 now?", default=True):
        click.echo(f"\n🔗 Connecting to {hostname} for stage 0 …")
        cmd_stage0 = "sudo -S -p '' /home/truffle/qa/scripts/stage0.sh"
        ok, _ = run_remote_command(hostname, cmd_stage0, allow_disconnect=True)

        # Stage 0 may reboot the machine; wait for it to come back.
        if not wait_for_ssh(hostname):
            raise click.Abort()

        if not ok:
            click.echo(click.style("Stage 0 failed – aborting.", fg="red"))
            raise click.Abort()
    else:
        click.echo("Exiting …")
        return

    # Stage 1
    if click.confirm("Would you like to run stage 1 now?", default=True):
        click.echo(f"\n🔗 Connecting to {hostname} for stage 1 …")
        cmd_stage1 = "sudo -S -p '' /home/truffle/qa/scripts/stage1.sh"
        ok, _ = run_remote_command(hostname, cmd_stage1)

        if not ok:
            click.echo(click.style("Stage 1 failed – aborting.", fg="red"))
            raise click.Abort()

        # Optional: wait in case stage 1 triggers a reboot as well.
        wait_for_ssh(hostname)
    else:
        click.echo("Exiting …")
        return

    # Stage 2
    if click.confirm("Are you ready to run stage 2?", default=True):
        click.echo(f"\n🔗 Connecting to {hostname} for stage 2 …")
        cmd_stage2 = "sudo -S -p '' /home/truffle/qa/scripts/stage2.sh"
        ok, _ = run_remote_command(hostname, cmd_stage2)

        if not ok:
            click.echo(click.style("Stage 2 failed.", fg="red"))
            raise click.Abort()

        # Final wait just in case
        wait_for_ssh(hostname)
    else:
        click.echo("Stage 2 skipped. Goodbye!")

    click.echo(click.style("\n✅ All requested stages completed successfully!", fg="green"))

if __name__ == '__main__':
    cli()
