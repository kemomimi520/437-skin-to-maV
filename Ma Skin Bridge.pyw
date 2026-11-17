import os
import sys
from pathlib import Path
runtime=Path(sys.executable).parent
if (runtime/'tcl/tcl8.6').is_dir():
    os.environ['TCL_LIBRARY']=str(runtime/'tcl/tcl8.6')
    os.environ['TK_LIBRARY']=str(runtime/'tcl/tk8.6')
from converter.gui import main
main()
