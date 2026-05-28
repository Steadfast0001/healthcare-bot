import socket
import re
import os

def get_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('10.255.255.255', 1))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

def update_env_files(ip):
    env_files = ['.env', 'flutter.env']
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    for file_name in env_files:
        file_path = os.path.join(base_dir, file_name)
        if not os.path.exists(file_path):
            print(f"File {file_path} not found. Skipping.")
            continue
            
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_content = re.sub(
                r'BACKEND_URL=http://[0-9\.]+:\d+',
                f'BACKEND_URL=http://{ip}:8001',
                content
            )
            
            if new_content != content:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f"Updated {file_name} with IP {ip}")
            else:
                print(f"{file_name} already up to date.")
        except Exception as e:
            print(f"Error updating {file_name}: {e}")

if __name__ == "__main__":
    ip = get_ip()
    print(f"Detected local IP: {ip}")
    update_env_files(ip)
