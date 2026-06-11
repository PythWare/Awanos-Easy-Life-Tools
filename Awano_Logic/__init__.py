def run_app():
    from .gui import run_app as gui_run_app

    gui_run_app()


__all__ = ["run_app"]
