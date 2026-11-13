#import "RPFPythonBridge.h"
#include <Python.h>
#include <stdlib.h>

static NSString *RPFJSONString(NSString *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value]
                                                   options:NSJSONWritingFragmentsAllowed
                                                     error:nil];
    NSString *array = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [array substringWithRange:NSMakeRange(1, array.length - 2)];
}

int RPFRunPythonScript(NSString *pythonHome,
                       NSString *scriptPath,
                       NSString *inputPath,
                       NSString *reportPath) {
    setenv("PYTHONHOME", pythonHome.fileSystemRepresentation, 1);
    setenv("PYTHONPATH", [scriptPath.stringByDeletingLastPathComponent fileSystemRepresentation], 1);

    if (!Py_IsInitialized()) {
        Py_Initialize();
    }
    if (!Py_IsInitialized()) {
        return -1;
    }

    NSString *code = [NSString stringWithFormat:
        @"import sys, runpy, contextlib\n"
         "sys.argv = [%@, %@]\n"
         "with open(%@, 'w', encoding='utf-8') as report_file:\n"
         "    with contextlib.redirect_stdout(report_file), contextlib.redirect_stderr(report_file):\n"
         "        runpy.run_path(sys.argv[0], run_name='__main__')\n",
        RPFJSONString(scriptPath),
        RPFJSONString(inputPath),
        RPFJSONString(reportPath)];

    return PyRun_SimpleStringFlags(code.UTF8String, NULL);
}
