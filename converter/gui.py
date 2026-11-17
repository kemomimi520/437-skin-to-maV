from __future__ import annotations
import ctypes
from ctypes import wintypes
from collections import deque
import os
from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from .msz import convert_msz


class Application(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('Ma Skin Bridge · Malody 4.3.7 → Malody V 原生 Key 转换器')
        self.geometry('740x430');self.minsize(580,340)
        self.configure(bg='#101722')
        self.messages=queue.Queue();self.pending=deque();self.busy=False
        style=ttk.Style(self);style.theme_use('clam')
        style.configure('.',font=('Microsoft YaHei UI',11),background='#101722',foreground='#e6edf3')
        style.configure('TButton',padding=(16,10),background='#167e85',foreground='#ffffff')
        frame=ttk.Frame(self,padding=24);frame.pack(fill='both',expand=True)
        ttk.Label(frame,text='把 MSZ 拖到这里',font=('Microsoft YaHei UI',24,'bold')).pack(anchor='w')
        ttk.Label(frame,text='转换为 Malody V 原生 Key (free=false) 皮肤包 .msp。',foreground='#b8d4de').pack(anchor='w',pady=(8,18))
        ttk.Button(frame,text='选择 MSZ 文件',command=self.choose).pack(anchor='w')
        self.status=ttk.Label(frame,text='就绪：拖拽或选择 .msz 开始转换（原生 Key 模式）',foreground='#b8d4de')
        self.status.pack(anchor='w',pady=(18,8))
        self.log=tk.Text(frame,bg='#182331',fg='#d8e8ef',relief='flat',wrap='word',height=7,padx=12,pady=10)
        self.log.pack(fill='both',expand=True)
        ttk.Label(frame,text='输出合规原生 Key .msp；线上上传、正常成绩上传及 Android 兼容性需在真实环境另行验证。',foreground='#b8d4de',font=('Microsoft YaHei UI',9)).pack(anchor='w',pady=(10,0))
        self.after(100,self.poll);self.after(200,self.enable_drop)
        self.protocol('WM_DELETE_WINDOW',self.close)

    def choose(self):
        files=filedialog.askopenfilenames(title='选择旧版 MSZ 皮肤',filetypes=[('Malody 旧版皮肤','*.msz')])
        if files:self.submit(files)

    def submit(self,files):
        self.pending.extend(Path(f) for f in files)
        self.run_next()

    def run_next(self):
        if self.busy or not self.pending:return
        source=self.pending.popleft();self.busy=True
        self.status.config(text=f'正在转换：{source.name}')
        self.log.insert('end',f'\n{source}\n');self.log.see('end')
        def worker():
            try:
                result=convert_msz(source,lambda text:self.messages.put(('progress',text)))
                text='\n'.join(str(p) for p in result) if isinstance(result,(list,tuple)) else str(result)
                self.messages.put(('success',text))
            except Exception as error:self.messages.put(('error',str(error)))
        threading.Thread(target=worker,daemon=True).start()

    def poll(self):
        try:
            while True:
                kind,text=self.messages.get_nowait()
                if kind=='progress':
                    self.status.config(text=text)
                    if text.startswith('提示：'):
                        self.log.insert('end',text+'\n');self.log.see('end')
                else:
                    self.busy=False
                    self.status.config(text='已生成 MSP' if kind=='success' else '转换失败')
                    self.log.insert('end',('已生成：' if kind=='success' else '失败：')+text+'\n')
                    self.log.see('end');self.run_next()
        except queue.Empty:pass
        self.after(100,self.poll)

    def enable_drop(self):
        if os.name!='nt':return
        user=ctypes.WinDLL('user32',use_last_error=True);shell=ctypes.WinDLL('shell32',use_last_error=True)
        user.GetParent.argtypes=[wintypes.HWND];user.GetParent.restype=wintypes.HWND
        hwnd=user.GetParent(self.winfo_id())
        shell.DragAcceptFiles.argtypes=[wintypes.HWND,wintypes.BOOL]
        shell.DragQueryFileW.argtypes=[wintypes.HANDLE,wintypes.UINT,wintypes.LPWSTR,wintypes.UINT];shell.DragQueryFileW.restype=wintypes.UINT
        shell.DragFinish.argtypes=[wintypes.HANDLE]
        callback=ctypes.WINFUNCTYPE(ctypes.c_ssize_t,wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM)
        setter=user.SetWindowLongPtrW;setter.argtypes=[wintypes.HWND,ctypes.c_int,ctypes.c_void_p];setter.restype=ctypes.c_void_p
        user.CallWindowProcW.argtypes=[ctypes.c_void_p,wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM];user.CallWindowProcW.restype=ctypes.c_ssize_t
        def procedure(window,msg,wp,lp):
            if msg==0x233:
                count=shell.DragQueryFileW(wp,0xffffffff,None,0)
                for i in range(count):
                    length=shell.DragQueryFileW(wp,i,None,0);buffer=ctypes.create_unicode_buffer(length+1);shell.DragQueryFileW(wp,i,buffer,length+1)
                    self.after(0,self.submit,[buffer.value])
                shell.DragFinish(wp);return 0
            return user.CallWindowProcW(self._oldproc,window,msg,wp,lp)
        self._drop_callback=callback(procedure);self._oldproc=setter(hwnd,-4,ctypes.cast(self._drop_callback,ctypes.c_void_p));self._drop_state=(setter,hwnd)
        shell.DragAcceptFiles(hwnd,True)

    def close(self):
        if self.busy:
            messagebox.showinfo('转换中','文件正在生成，请等待当前转换结束。');return
        if hasattr(self,'_drop_state'):
            setter,hwnd=self._drop_state;setter(hwnd,-4,self._oldproc)
        self.destroy()


def main():
    import sys
    app=Application()
    if sys.argv[1:]:app.after(250,app.submit,sys.argv[1:])
    app.mainloop()
