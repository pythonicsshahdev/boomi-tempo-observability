# port_holder <port>: prints what holds the port, nothing if free or held only by this stack.
port_holder() {
  local p=$1 names others
  names=$(docker ps --filter "publish=$p" --format '{{.Names}}' 2>/dev/null)
  if [ -n "$names" ]; then
    others=$(echo "$names" | grep -v '^boomi-tempo-' | head -1)
    [ -n "$others" ] && echo "$others"
    return 0
  fi
  lsof -nP -iTCP:"$p" -sTCP:LISTEN -Fc 2>/dev/null | sed -n 's/^c//p' | head -1
}
