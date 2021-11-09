### eth下cmd的rlpdump子包,该包的主要作用从给定文件中转储RLP数据以可读的形式．如果文件名被省略，数据将从stdin中读取

　 /rlpdump

##### 解码rlp的数据


###### rlpdump的command的help

```
Usage: /tmp/___cmd_rlpdump_test [-noascii] [-hex <data>] [filename]
  -hex string
    	dump given hex data
  -noascii
    	don't print ASCII strings readably
  -single
    	print only the first element, discard the rest

Dumps RLP data from the given file in readable form.
If the filename is omitted, data is read from stdin.

```


###### example1:
```
  demo command: --hex f872f870845609a1ba64c0b8660480136e573eb81ac4a664f8f76e4887ba927f791a053ec5ff580b1037a8633320ca70f8ec0cdea59167acaa1debc07bc0a0b3a5b41bdf0cb4346c18ddbbd2cf222f54fed795dde94417d2e57f85a580d87238efc75394ca4a92cfe6eb9debcc3583c26fee8580
  success_result_demo:
    [
      [
        5609a1ba,
        "d",
        [],
        0480136e573eb81ac4a664f8f76e4887ba927f791a053ec5ff580b1037a8633320ca70f8ec0cdea59167acaa1debc07bc0a0b3a5b41bdf0cb4346c18ddbbd2cf222f54fed795dde94417d2e57f85a580d87238efc75394ca4a92cfe6eb9debcc3583c26fee85,
        "",
      ],
    ]
```

###### example2:

```
  demo command: --noascii --hex CE0183FFFFFFC4C304050583616263
  success_result_demo:
    [
      01,
      ffffff,
      [
        [
          04,
          05,
          05,
        ],
      ],
      616263,
    ]



```




