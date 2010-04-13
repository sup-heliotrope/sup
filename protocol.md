Redwood Protocol
================

The server begins by sending a line of the form `Redwood <ver> <encodings>
<extensions>`, where `ver` is the major protocol version (1), encodings is a
comma-separated list of supported message encodings (e.g. `json,bert,marshal`),
and `extensions` is a comma-separated list of protocol extensions. The server
must advertise at least one encoding. A zero-length list of extensions is
represented by `none`. The client replies in the same format, with the
restrictions that the protocol version must match, `encodings` and `extensions`
must be subsets of what the server advertised, and there must be exactly 1
encoding specified.

Requests and responses are represented as `[type, params]`, where `type`
is a lowercase string corresponding to one of the message types specified
below and `params` is a dictionary with string keys.

Requests
--------

There may be zero or more replies to a request. Multiple requests may be
issued concurrently. There is an implicit, optional, opaque `tag` parameter to
every request which will be returned in all replies to the request to
aid clients in keeping multiple requests in flight. `tag` may be an
arbitrary datastructure and for the purposes of Cancel defaults to nil.

### Query
Send a Message response for each hit on `query` starting at `offset`
and sending a maximum of `limit` Messages responses. `raw` controls
whether the raw message text is included in the response.

#### Parameters
*   `query`: Query
*   `offset`: int
*   `limit`: int
*   `raw`: boolean

#### Responses
*   multiple Message
*   one Done after all Messages


### Count
Send a count reply with the number of hits for `query`.

#### Parameters
*   `query`: Query

#### Responses
*   one Count


### Label
Modify the labels on all messages matching `query`. First removes the
labels in `remove` then adds those in `add`.

#### Parameters
*   `query`: Query
*   `add`: string list
*   `remove`: string list

#### Responses
*   one Done


### Add
Add a message to the database. `raw` is the normal RFC 2822 message text.

#### Parameters
*   `raw`: string
*   `labels`: string list

#### Responses
*   one Done


### Stream
Sends a Message response whenever a new message that matches `query` is
added with the Add request. This request will not terminate until a
corresponding Cancel request is sent.

#### Parameters
*   `query`: Query

#### Responses
multiple Message


### Cancel
Cancels all active requests with tag `target`. This is only required to
be implemented for the Stream request.

#### Parameters
*   `target`: string

#### Responses
one Done



Responses
---------

### Done
Signifies that a request has completed successfully.


### Message
Represents a query result. If `raw` is present it is the raw message
text that was previously a parameter to the Add request.

#### Parameters
*   `summary`: Summary
*   `raw`: optional string


### Count
`count` is the number of messages matched.

#### Parameters
*   `count`: int


### Error

#### Parameters
*   `type`: string
*   `message`: string



Datatypes
---------

### Query
Recursive prefix-notation datastructure describing a boolean condition.
Where `a` and `b` are Queries and `field` and `value` are strings, a
Query can be any of the following:

*   `[:and, a, b, ...]`
*   `[:or, a, b, ...]`
*   `[:not, a, b]`
*   `[:term, field, value]`


### Summary
*   `message_id`: string
*   `date`: time
*   `from`: Person
*   `to`, `cc`, `bcc`: Person list
*   `subject`: string
*   `refs`: string list
*   `replytos`: string list
*   `labels`: string list


### Person
*   `name`: string
*   `email`: string


TODO
----

*   Protocol negotiation
   -   Version
   -   Compression (none, gzip, ...)
*   Specify string encodings
