import java.awt.Dialog;
import java.applet.Applet;
import java.awt.Frame;

class ImportExportAppletDialog
extends Dialog
implements ImportExportDialog
{
    Action type;
    CirSim cframe;
    String circuitDump;

    ImportExportAppletDialog(CirSim f, Action type)
    throws Exception
    {
	super(f, (type == Action.EXPORT) ? "Export" : "Import", false);
	this.type = type;
	cframe = f;
	if ( cframe.applet == null )
	    throw new Exception("Not running as an applet!");
    }

    public void setDump(String dump)
    {
	circuitDump = dump;
    }

	public void execute()
	{
	    try
	    {
	    Object window = getBrowserWindow(cframe.applet);
	    if (window == null)
		throw new Exception("Browser JavaScript bridge is unavailable.");

	    if ( type == Action.EXPORT )
	    {
		//cframe.setVisible(false);
		invokeBrowserCall(window, "exportCircuit", circuitDump);
	    }
	    else
	    {
		//cframe.setVisible(false);
		circuitDump = (String) invokeBrowserEval(window, "importCircuit()");
		cframe.readSetup( circuitDump );
	    }
	}
	catch (Exception e)
	{
	    e.printStackTrace();
	}
	}

	private Object getBrowserWindow(Applet applet) throws Exception
	{
	    Class<?> jsClass = Class.forName("netscape.javascript.JSObject");
	    return jsClass.getMethod("getWindow", Applet.class).invoke(null, applet);
	}

	private void invokeBrowserCall(Object window, String functionName, Object arg) throws Exception
	{
	    window.getClass().getMethod("call", String.class, Object[].class)
		.invoke(window, functionName, new Object[] { arg });
	}

	private Object invokeBrowserEval(Object window, String script) throws Exception
	{
	    return window.getClass().getMethod("eval", String.class)
		.invoke(window, script);
	}
}
