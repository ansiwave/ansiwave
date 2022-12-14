when defined(release):
  switch("define", "defaultGetAddress:https://bbs.ansiwave.net/bbs/")
  switch("define", "defaultPostAddress:https://post.ansiwave.net")
  switch("define", "defaultBoard:kEKgeSd3-74Uy0bfOOJ9mj0qW3KpMpXBGrrQdUv190E")
else:
  switch("define", "defaultGetAddress:http://localhost:3000")
  switch("define", "defaultPostAddress:http://localhost:3000")
  switch("define", "defaultBoard:Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE")

--app:gui
--define:chafa
--threads:on
--define:staticSqlite
--gc:orc
