from multiprocessing import freeze_support
import os, sys
from pathlib import Path

def configure_launch_directory():
    app_dir = Path(__file__).resolve().parent
    os.chdir(app_dir)

    app_dir_text = str(app_dir)
    if app_dir_text not in sys.path:
        sys.path.insert(0, app_dir_text)

    return app_dir


def main():
    freeze_support()
    configure_launch_directory()

    from Awano_Logic import run_app

    run_app()


if __name__ == "__main__":
    main()
