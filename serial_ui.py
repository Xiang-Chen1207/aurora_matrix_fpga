#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
矩阵计算器串口UI界面
基于FPGA矩阵计算项目的UART通信协议
"""

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import serial
import serial.tools.list_ports
import threading
import time
import queue

class SerialUI:
    def __init__(self, root):
        self.root = root
        self.root.title("矩阵计算器串口调试助手")
        self.root.geometry("800x600")
        
        # 串口相关变量
        self.serial_port = None
        self.is_connected = False
        self.receive_queue = queue.Queue()
        
        # 创建界面
        self.create_widgets()
        
        # 启动接收线程
        self.start_receive_thread()
    
    def create_widgets(self):
        # 主框架
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # 配置行列权重
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(1, weight=1)
        main_frame.rowconfigure(3, weight=1)
        
        # 串口设置区域
        serial_frame = ttk.LabelFrame(main_frame, text="串口设置", padding="5")
        serial_frame.grid(row=0, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 10))
        serial_frame.columnconfigure(1, weight=1)
        
        # 串口选择
        ttk.Label(serial_frame, text="串口号:").grid(row=0, column=0, sticky=tk.W, padx=(0, 5))
        self.port_combo = ttk.Combobox(serial_frame, width=15)
        self.port_combo.grid(row=0, column=1, sticky=(tk.W, tk.E), padx=(0, 10))
        
        # 刷新串口按钮
        self.refresh_btn = ttk.Button(serial_frame, text="刷新", command=self.refresh_ports)
        self.refresh_btn.grid(row=0, column=2, padx=(0, 10))
        
        # 波特率
        ttk.Label(serial_frame, text="波特率:").grid(row=0, column=3, sticky=tk.W, padx=(0, 5))
        self.baud_combo = ttk.Combobox(serial_frame, width=10, values=["9600", "19200", "38400", "57600", "115200"])
        self.baud_combo.set("115200")
        self.baud_combo.grid(row=0, column=4, sticky=(tk.W, tk.E), padx=(0, 10))
        
        # 连接/断开按钮
        self.connect_btn = ttk.Button(serial_frame, text="连接", command=self.toggle_connection)
        self.connect_btn.grid(row=0, column=5)
        
        # 发送区域
        send_frame = ttk.LabelFrame(main_frame, text="发送数据", padding="5")
        send_frame.grid(row=1, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 10))
        send_frame.columnconfigure(0, weight=1)
        
        # 发送文本框
        self.send_text = tk.Text(send_frame, height=3, width=50)
        self.send_text.grid(row=0, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 5))
        
        # 发送按钮
        self.send_btn = ttk.Button(send_frame, text="发送", command=self.send_data)
        self.send_btn.grid(row=1, column=0, sticky=tk.W)
        
        # 清空发送按钮
        self.clear_send_btn = ttk.Button(send_frame, text="清空", command=self.clear_send)
        self.clear_send_btn.grid(row=1, column=1, sticky=tk.W, padx=(5, 0))
        
        # 接收区域
        receive_frame = ttk.LabelFrame(main_frame, text="接收数据", padding="5")
        receive_frame.grid(row=2, column=0, columnspan=2, sticky=(tk.W, tk.E, tk.N, tk.S), pady=(0, 10))
        receive_frame.columnconfigure(0, weight=1)
        receive_frame.rowconfigure(0, weight=1)
        
        # 接收文本框
        self.receive_text = scrolledtext.ScrolledText(receive_frame, height=15, width=80)
        self.receive_text.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # 清空接收按钮
        self.clear_receive_btn = ttk.Button(receive_frame, text="清空接收", command=self.clear_receive)
        self.clear_receive_btn.grid(row=1, column=0, sticky=tk.W, pady=(5, 0))
        
        # 状态栏
        self.status_var = tk.StringVar(value="就绪")
        status_bar = ttk.Label(main_frame, textvariable=self.status_var, relief=tk.SUNKEN)
        status_bar.grid(row=3, column=0, columnspan=2, sticky=(tk.W, tk.E))
        
        # 初始化串口列表
        self.refresh_ports()
        
        # 绑定回车键发送
        self.root.bind('<Return>', lambda event: self.send_data())
    
    def refresh_ports(self):
        """刷新可用串口列表"""
        ports = [port.device for port in serial.tools.list_ports.comports()]
        self.port_combo['values'] = ports
        if ports:
            self.port_combo.set(ports[0])
    
    def toggle_connection(self):
        """连接/断开串口"""
        if not self.is_connected:
            self.connect_serial()
        else:
            self.disconnect_serial()
    
    def connect_serial(self):
        """连接串口"""
        port = self.port_combo.get()
        baud = self.baud_combo.get()
        
        if not port:
            messagebox.showerror("错误", "请选择串口号")
            return
        
        try:
            self.serial_port = serial.Serial(
                port=port,
                baudrate=int(baud),
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=1
            )
            self.is_connected = True
            self.connect_btn.config(text="断开")
            self.status_var.set(f"已连接到 {port} ({baud} baud)")
            self.receive_text.insert(tk.END, f"=== 连接到 {port} ===\n")
            self.receive_text.see(tk.END)
            
        except Exception as e:
            messagebox.showerror("连接错误", f"无法连接到串口: {str(e)}")
    
    def disconnect_serial(self):
        """断开串口"""
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
        self.is_connected = False
        self.connect_btn.config(text="连接")
        self.status_var.set("已断开连接")
        self.receive_text.insert(tk.END, "=== 断开连接 ===\n")
        self.receive_text.see(tk.END)
    
    def send_data(self):
        """发送数据"""
        if not self.is_connected:
            messagebox.showerror("错误", "请先连接串口")
            return
        
        data = self.send_text.get("1.0", tk.END).strip()
        if not data:
            messagebox.showwarning("警告", "发送内容不能为空")
            return
        
        try:
            # 添加换行符
            data_to_send = data + '\n'
            self.serial_port.write(data_to_send.encode('utf-8'))
            
            # 在接收区显示发送的数据
            self.receive_text.insert(tk.END, f"[发送] {data}\n")
            self.receive_text.see(tk.END)
            
            # 清空发送区
            self.send_text.delete("1.0", tk.END)
            
        except Exception as e:
            messagebox.showerror("发送错误", f"发送失败: {str(e)}")
    
    def clear_send(self):
        """清空发送区"""
        self.send_text.delete("1.0", tk.END)
    
    def clear_receive(self):
        """清空接收区"""
        self.receive_text.delete("1.0", tk.END)
    
    def start_receive_thread(self):
        """启动接收线程"""
        self.receive_thread = threading.Thread(target=self.receive_data, daemon=True)
        self.receive_thread.start()
        
        # 启动UI更新线程
        self.root.after(100, self.update_ui)
    
    def receive_data(self):
        """接收数据线程"""
        while True:
            if self.is_connected and self.serial_port and self.serial_port.is_open:
                try:
                    if self.serial_port.in_waiting > 0:
                        data = self.serial_port.readline().decode('utf-8', errors='ignore').strip()
                        if data:
                            self.receive_queue.put(data)
                    else:
                        time.sleep(0.01)
                except Exception as e:
                    print(f"接收错误: {e}")
                    time.sleep(0.1)
            else:
                time.sleep(0.1)
    
    def update_ui(self):
        """更新UI显示接收到的数据"""
        try:
            while not self.receive_queue.empty():
                data = self.receive_queue.get_nowait()
                self.receive_text.insert(tk.END, f"[接收] {data}\n")
                self.receive_text.see(tk.END)
        except queue.Empty:
            pass
        
        # 继续定时更新
        self.root.after(100, self.update_ui)
    
    def on_closing(self):
        """关闭窗口时的清理工作"""
        if self.is_connected:
            self.disconnect_serial()
        self.root.destroy()

def main():
    root = tk.Tk()
    app = SerialUI(root)
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    root.mainloop()

if __name__ == "__main__":
    main()