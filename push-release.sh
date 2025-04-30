
print_delim()
{
  echo "--------------------------------------------------------------------------------"
}

header()
{
  echo
  print_delim
  echo "$1"
  print_delim
  echo
}


RELEASE=v$(cat version.txt)

header "Pushing release $RELEASE"

git tag -d "$RELEASE"
git tag "$RELEASE"
git push --force origin "$RELEASE"

