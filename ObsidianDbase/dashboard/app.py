# app.py
# VaultWatch Dashboard - Flask backend
# Connects to VaultWatch on ORIONVI\SQLEXPRESS and serves chart data

import pyodbc
from flask import Flask, render_template, jsonify

app = Flask(__name__)

CONNECTION_STRING = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=ORIONVI\\SQLEXPRESS;"
    "DATABASE=VaultWatch;"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)

def get_connection():
    return pyodbc.connect(CONNECTION_STRING)


# ----------------------------------------------------------------------------
# API ENDPOINTS
# ----------------------------------------------------------------------------

@app.route("/api/vault-size-over-time")
def vault_size_over_time():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT RunID, RunTimestamp, TotalFiles, TotalSizeMB
        FROM SnapshotRuns
        ORDER BY RunID ASC
    """)
    rows = cursor.fetchall()
    conn.close()
    return jsonify([{
        "run_id":      row[0],
        "timestamp":   row[1].strftime("%Y-%m-%d %H:%M"),
        "total_files": row[2],
        "total_size":  float(row[3])
    } for row in rows])


@app.route("/api/files-per-folder")
def files_per_folder():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT TOP 15 FolderName, COUNT(*) AS FileCount
        FROM FileSnapshots
        WHERE RunID = (SELECT MAX(RunID) FROM SnapshotRuns)
        GROUP BY FolderName
        ORDER BY FileCount DESC
    """)
    rows = cursor.fetchall()
    conn.close()
    return jsonify([{
        "folder": row[0],
        "count":  row[1]
    } for row in rows])


@app.route("/api/largest-files")
def largest_files():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT TOP 10 FileName, FolderName, SizeBytes, LineCount
        FROM FileSnapshots
        WHERE RunID = (SELECT MAX(RunID) FROM SnapshotRuns)
        ORDER BY SizeBytes DESC
    """)
    rows = cursor.fetchall()
    conn.close()
    return jsonify([{
        "filename":  row[0],
        "folder":    row[1],
        "size":      row[2],
        "lines":     row[3]
    } for row in rows])


@app.route("/api/recent-changes")
def recent_changes():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        DECLARE @RunA INT = (SELECT MIN(RunID) FROM (SELECT TOP 2 RunID FROM SnapshotRuns ORDER BY RunID DESC) x);
        DECLARE @RunB INT = (SELECT MAX(RunID) FROM (SELECT TOP 2 RunID FROM SnapshotRuns ORDER BY RunID DESC) x);

        SELECT 'MODIFIED' AS ChangeType, b.FileName, b.FolderName,
               a.SizeBytes AS Before, b.SizeBytes AS After, b.RelativePath
        FROM FileSnapshots a
        JOIN FileSnapshots b ON a.RelativePath = b.RelativePath
            AND a.RunID = @RunA AND b.RunID = @RunB
        WHERE a.ModifiedTime <> b.ModifiedTime OR a.SizeBytes <> b.SizeBytes

        UNION ALL

        SELECT 'ADDED', b.FileName, b.FolderName, NULL, b.SizeBytes, b.RelativePath
        FROM FileSnapshots b
        WHERE b.RunID = @RunB
        AND b.RelativePath NOT IN (SELECT RelativePath FROM FileSnapshots WHERE RunID = @RunA)

        UNION ALL

        SELECT 'DELETED', a.FileName, a.FolderName, a.SizeBytes, NULL, a.RelativePath
        FROM FileSnapshots a
        WHERE a.RunID = @RunA
        AND a.RelativePath NOT IN (SELECT RelativePath FROM FileSnapshots WHERE RunID = @RunB)

        ORDER BY ChangeType, FileName;
    """)
    rows = cursor.fetchall()
    conn.close()
    return jsonify([{
        "change_type":   row[0],
        "filename":      row[1],
        "folder":        row[2],
        "size_before":   row[3],
        "size_after":    row[4],
        "relative_path": row[5]
    } for row in rows])


# ----------------------------------------------------------------------------
# MAIN ROUTE
# ----------------------------------------------------------------------------

@app.route("/")
def index():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT TOP 1 RunID, RunTimestamp, TotalFiles, TotalSizeMB FROM SnapshotRuns ORDER BY RunID DESC")
    row = cursor.fetchone()
    conn.close()
    latest = {
        "run_id":      row[0],
        "timestamp":   row[1].strftime("%Y-%m-%d %H:%M"),
        "total_files": row[2],
        "total_size":  float(row[3])
    }
    return render_template("index.html", latest=latest)


if __name__ == "__main__":
    app.run(debug=True, host="127.0.0.1", port=47800)
