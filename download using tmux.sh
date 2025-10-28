# to use tmux
dnf install -y tmux
# to open up a session
tmux new -s download # you can set any name you want 
# in your session you can perform download
# to come out of the session and let tmux run in background
# Ctrl+b d → detach
# To check your session
tmux attach -t download 
# to exit the session after download
tmux kill-session -t download
# if you create multiple session and forget name
tmux ls