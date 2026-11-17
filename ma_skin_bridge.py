if __name__ == '__main__':
    import sys
    from pathlib import Path
    if len(sys.argv)>1 and Path(sys.argv[1]).suffix.lower()=='.msz':
        from converter.msz import main
    else:
        from converter.cli import main
    raise SystemExit(main())
