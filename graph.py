import sys
import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.dates import DateFormatter


def main():
    if len(sys.argv) < 2:
        print("Usage: python graph.py <path/to/stage*_burn_log.csv>")
        sys.exit(1)

    csv_path = sys.argv[1]
    if not os.path.isfile(csv_path):
        print(f"File not found: {csv_path}")
        sys.exit(1)

    # Ask user for a short description (sub-heading)
    sub_heading = input("Enter graph name / description (will appear as sub-heading): ")

    df = pd.read_csv(csv_path)

    # Cast columns to proper dtypes
    df['time'] = pd.to_datetime(df['time'])
    numeric_cols = [
        'stage', 'Temp tj', 'Power TOT', 'GPU', 'Fan pwmfan0',
        'CPU1', 'CPU2', 'CPU3', 'CPU4', 'CPU5', 'CPU6', 'CPU7', 'CPU8'
    ]
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')
        else:
            df[col] = np.nan  # create empty column if missing

    # Compute average CPU utilisation if individual cores present
    cpu_cols = [c for c in df.columns if c.startswith('CPU')]
    if cpu_cols:
        df['CPU_avg'] = df[cpu_cols].mean(axis=1, skipna=True)
    else:
        df['CPU_avg'] = np.nan

    # Determine stage transition index (0 -> 1)
    stage_transition_time = None
    if 'stage' in df.columns:
        stage_diff = df['stage'].diff().fillna(0)
        transition_rows = df.loc[stage_diff > 0]
        if not transition_rows.empty:
            stage_transition_time = transition_rows.iloc[0]['time']

    # Detect shutdown row (last row with many NaNs)
    shutdown_time = None
    shutdown_threshold = 0.5  # >50% NaNs considered shutdown marker row
    nan_ratio_last = df.iloc[-1].isna().mean()
    if nan_ratio_last > shutdown_threshold:
        shutdown_time = df.iloc[-1]['time']
        # Drop the shutdown marker row from plotting
        df = df.iloc[:-1]

    # Build figure with 5 stacked sub-plots sharing the x-axis
    fig, axes = plt.subplots(5, 1, figsize=(14, 12), sharex=True)

    # 1. Temperature (Temp tj)
    axes[0].plot(df['time'], df['Temp tj'], color='tab:red')
    axes[0].set_ylabel('Temp tj (°C)')
    axes[0].set_title('Temperature')

    # 2. Power draw
    axes[1].plot(df['time'], df['Power TOT'], color='tab:purple')
    axes[1].set_ylabel('Power (W)')
    axes[1].set_title('Total Power Draw')

    # 3. CPU utilisation
    axes[2].plot(df['time'], df['CPU_avg'], color='tab:green')
    axes[2].set_ylabel('CPU Util (%)')
    axes[2].set_title('Average CPU Utilisation')

    # 4. GPU utilisation
    axes[3].plot(df['time'], df['GPU'], color='tab:blue')
    axes[3].set_ylabel('GPU Util (%)')
    axes[3].set_title('GPU Utilisation')

    # 5. Fan PWM
    axes[4].plot(df['time'], df['Fan pwmfan0'], color='tab:orange')
    axes[4].set_ylabel('Fan PWM')
    axes[4].set_title('Fan Speed (PWM value)')

    # Format the x-axis dates nicely on the last axis
    date_fmt = DateFormatter('%H:%M:%S')
    axes[-1].xaxis.set_major_formatter(date_fmt)
    plt.xticks(rotation=45, ha='right')

    # Add vertical lines for stage transition and shutdown events
    # for ax in axes:
    #     if stage_transition_time is not None and pd.notna(stage_transition_time):
    #         ax.axvline(stage_transition_time, color='grey', linestyle='--', label='Stage 0 → 1')
    #     if shutdown_time is not None and pd.notna(shutdown_time):
    #         ax.axvline(shutdown_time, color='red', linestyle='-.', label='Shutdown')

    # Avoid duplicate legend entries
    handles, labels = axes[0].get_legend_handles_labels()
    if handles:
        fig.legend(handles, labels, loc='upper right')

    # Titles
    fig.suptitle('GPU Burn Test', fontsize=16, fontweight='bold')
    if sub_heading:
        fig.subplots_adjust(top=0.9)
        fig.text(0.5, 0.92, sub_heading, ha='center', fontsize=12)

    fig.tight_layout(rect=[0, 0, 1, 0.9])

    # Save & show
    out_png = os.path.splitext(os.path.basename(csv_path))[0] + '.png'
    plt.savefig(out_png, dpi=300)
    print(f"Graph saved to {out_png}")
    plt.show()


if __name__ == '__main__':
    main()

