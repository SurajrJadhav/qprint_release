"""
System Diagnostic Script
Checks if all prerequisites are installed
"""

import subprocess
import sys
import os

def check_command(command, name):
    """Check if a command is available"""
    try:
        result = subprocess.run(
            [command, '--version'] if command != 'node' else [command, '-v'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            version = result.stdout.strip().split('\n')[0]
            print(f"✓ {name}: {version}")
            return True
        else:
            print(f"✗ {name}: Not found")
            return False
    except (FileNotFoundError, subprocess.TimeoutExpired):
        print(f"✗ {name}: Not installed or not in PATH")
        return False
    except Exception as e:
        print(f"✗ {name}: Error checking - {e}")
        return False

def check_postgres():
    """Check if PostgreSQL is running"""
    try:
        # Try to connect to PostgreSQL
        result = subprocess.run(
            ['psql', '--version'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            print(f"✓ PostgreSQL client: {result.stdout.strip()}")
            return True
        else:
            print("✗ PostgreSQL: Not found")
            return False
    except FileNotFoundError:
        print("✗ PostgreSQL: Not installed")
        return False
    except Exception as e:
        print(f"⚠ PostgreSQL: {e}")
        return False

def main():
    print("\n" + "="*60)
    print("  System Diagnostics - File Sharing App".center(60))
    print("="*60 + "\n")
    
    results = {}
    
    # Check Python
    print(f"✓ Python: {sys.version.split()[0]}")
    results['python'] = True
    
    # Check Go
    results['go'] = check_command('go', 'Go')
    
    # Check Node.js
    results['node'] = check_command('node', 'Node.js')
    
    # Check npm
    results['npm'] = check_command('npm', 'npm')
    
    # Check PostgreSQL
    results['postgres'] = check_postgres()
    
    # Summary
    print("\n" + "="*60)
    print("  Summary".center(60))
    print("="*60 + "\n")
    
    missing = []
    if not results.get('node') or not results.get('npm'):
        missing.append("Node.js/npm")
    if not results.get('postgres'):
        missing.append("PostgreSQL")
    
    if missing:
        print("❌ MISSING PREREQUISITES:")
        for item in missing:
            print(f"   - {item}")
        
        print("\n📋 INSTALLATION INSTRUCTIONS:")
        
        if "Node.js/npm" in missing:
            print("\n1. Install Node.js:")
            print("   Option A (Recommended):")
            print("     winget install OpenJS.NodeJS.LTS")
            print("   Option B:")
            print("     Download from: https://nodejs.org/")
        
        if "PostgreSQL" in missing:
            print("\n2. Install PostgreSQL:")
            print("   Option A (Recommended):")
            print("     winget install PostgreSQL.PostgreSQL")
            print("   Option B:")
            print("     Download from: https://www.postgresql.org/download/windows/")
        
        print("\n3. After installation:")
        print("   - RESTART your terminal")
        print("   - Run this script again to verify")
        print("   - See INSTALL.md for detailed setup")
        
    else:
        print("✅ ALL PREREQUISITES INSTALLED!")
        print("\nNext steps:")
        print("1. Create PostgreSQL database: CREATE DATABASE filesharing;")
        print("2. Update backend/.env with your PostgreSQL password")
        print("3. Run: cd frontend && npm install")
        print("4. Run: python manage.py start")
    
    print("\n" + "="*60 + "\n")

if __name__ == "__main__":
    main()
