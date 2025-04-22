# scipt symlink all file in folder
import os
import subprocess
import argparse

parser = argparse.ArgumentParser(description="symlink all file in folder v1.0.0")
parser.add_argument("--input-folder", type=str, required=True, help="Path to input folder.")
parser.add_argument("--output-folder", type=str, required=True, help="Path to output folder.")

args = parser.parse_args()

input_folder = args.input_folder
output_folder = args.output_folder

files = sorted([f for f in os.listdir(input_folder) if os.path.isfile(os.path.join(input_folder, f))])

for _, filename in enumerate(files):
    in_file = os.path.join(input_folder, filename)
    command = ["ln", "-sf", in_file, output_folder]
    subprocess.run(command)


print("Symlink all file success")
