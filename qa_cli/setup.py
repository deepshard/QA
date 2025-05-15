from setuptools import setup, find_packages

setup(
    name="qa_cli",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "click>=8.1.7",
        "paramiko>=3.4.0",
        "python-dotenv>=1.0.1",
    ],
    entry_points={
        "console_scripts": [
            "qa-cli=qa_cli.cli:cli",
        ],
    },
) 