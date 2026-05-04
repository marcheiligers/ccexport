# TODO

## Investigate JSONL entries without timestamps

Some JSONL entries have no `timestamp` key. Currently `message_in_date_range?` treats them as in-range (includes them). It may be more correct to inherit the timestamp of the preceding entry — investigate whether that's the pattern in practice and update accordingly.
