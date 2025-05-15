# QA CLI Tool

A command-line interface tool designed to automate and streamline the QA process for truffle machines.

## Installation

1. Clone this repository:
```bash
git clone <repository-url>
cd qa_cli
```

2. Install the required dependencies:
```bash
pip install -e .
```

Required dependencies:
- click
- paramiko

## Usage

The QA CLI tool provides a simple interface to run various QA stages on truffle machines. 

Basic command:
```bash
qa_cli qa --truffle-id truffle-XXXX
```

Or simply run:
```bash
qa_cli qa
```
And you'll be prompted to enter the truffle ID.

### Truffle ID Format
- The truffle ID must be in the format `truffle-XXXX` where X is a digit
- Example: `truffle-2000`

## How It Works

The QA CLI tool executes a series of stages on the target truffle machine:

### Stage 0
- Initial setup and configuration
- May trigger a machine reboot
- The tool automatically waits for the machine to come back online

### Stage 1
- Secondary configuration phase
- Executes after Stage 0 completion
- May also trigger a reboot

### Stage 2
- Final configuration stage
- Runs after successful completion of Stage 1

