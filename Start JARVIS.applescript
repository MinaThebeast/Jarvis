on run
    set projectPath to POSIX path of ((path to desktop folder as text) & "Jarvis V1.0.3")
    set launchScript to quoted form of (projectPath & "/launch-jarvis.sh")
    do shell script "cd " & quoted form of projectPath & " && " & launchScript & " > /tmp/jarvis-launch.log 2>&1 &"
end run
