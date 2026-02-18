grep -E "source ${WSW_REPO_TOP}/source_all_env.sh" ~/.zshrc &>/dev/null

if [[ $? -ne 0 ]]; then
    echo "source ${WSW_REPO_TOP}/source_all_env.sh" >> ~/.zshrc
fi
