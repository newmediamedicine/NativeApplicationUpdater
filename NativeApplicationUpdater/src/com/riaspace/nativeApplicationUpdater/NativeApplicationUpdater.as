package com.riaspace.nativeApplicationUpdater
{
	import air.update.events.DownloadErrorEvent;
	import air.update.events.StatusUpdateErrorEvent;
	import air.update.events.StatusUpdateEvent;
	import air.update.events.UpdateEvent;

	import com.adobe.nativeExtensions.Vibration;

	import com.riaspace.nativeApplicationUpdater.utils.HdiutilHelper;
	
	import flash.desktop.NativeApplication;
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.net.URLStream;
	import flash.system.Capabilities;
	import flash.utils.ByteArray;
	import flash.utils.setTimeout;

	[Event(name="initialized", type="air.update.events.UpdateEvent")]
	[Event(name="checkForUpdate", type="air.update.events.UpdateEvent")]
	[Event(name="updateStatus",type="air.update.events.StatusUpdateEvent")]
	[Event(name="updateError",type="air.update.events.StatusUpdateErrorEvent")]
	[Event(name="downloadStart",type="air.update.events.UpdateEvent")]
	[Event(name="downloadError",type="air.update.events.DownloadErrorEvent")]
	[Event(name="downloadComplete",type="air.update.events.UpdateEvent")]
	[Event(name="progress",type="flash.events.ProgressEvent")]
	[Event(name="error",type="flash.events.ErrorEvent")]
	
	public class NativeApplicationUpdater extends EventDispatcher
	{
		
		namespace UPDATE_XMLNS_1_0 = "http://ns.riaspace.com/air/framework/update/description/1.0";
		
		namespace UPDATE_XMLNS_1_1 = "http://ns.riaspace.com/air/framework/update/description/1.1";
		
		/**
		 * The updater has not been initialized.
		 **/
		public static const UNINITIALIZED:String = "UNINITIALIZED";
		
		/**
		 * The updater is initializing.
		 **/
		public static const INITIALIZING:String = "INITIALIZING";
		
		/**
		 * The updater has been initialized.
		 **/
		public static const READY:String = "READY";
		
		/**
		 * The updater has not yet checked for the update descriptor file.
		 **/
		public static const BEFORE_CHECKING:String = "BEFORE_CHECKING";
		
		/**
		 * The updater is checking for an update descriptor file.
		 **/
		public static const CHECKING:String = "CHECKING";
		
		/**
		 * The update descriptor file is available.
		 **/
		public static const AVAILABLE:String = "AVAILABLE";

		/**
		 * The updater is downloading the AIR file.
		 **/
		public static const DOWNLOADING:String = "DOWNLOADING";
		
		/**
		 * The updater has downloaded the AIR file.
		 **/
		public static const DOWNLOADED:String = "DOWNLOADED";
		
		/**
		 * The updater is installing the AIR file.
		 **/
		public static const INSTALLING:String = "INSTALLING";

		/**
		 * URL specifying the location of the update descriptor XML file to use for updating the application.
		 */
		[Bindable]		
		public var updateURL:String;
		
		protected var _isNewerVersionFunction:Function;
		
		protected var _updateDescriptor:XML;
		
		protected var _updateVersion:String;
		
		protected var _updatePackageURL:String;
		
		protected var _updateDescription:String;

		protected var _currentVersion:String;
		
		protected var _downloadedFile:File;
		
		protected var _installerType:String;
		
		protected var _currentState:String = UNINITIALIZED;
		
		protected var updateDescriptorLoader:URLLoader;
		
		protected var os:String = Capabilities.os.toLowerCase();

		protected var manufacturer:String = Capabilities.manufacturer.toLowerCase();

		protected var urlStream:URLStream;
		
		protected var fileStream:FileStream;
		
		public function NativeApplicationUpdater()
		{
		}
		
		public function initialize():void
		{
			if (currentState == UNINITIALIZED)
			{
				currentState = INITIALIZING;
				
				var applicationDescriptor:XML = NativeApplication.nativeApplication.applicationDescriptor;
				var xmlns:Namespace = new Namespace(applicationDescriptor.namespace());
				
				if (xmlns.uri == "http://ns.adobe.com/air/application/2.0")
					currentVersion = applicationDescriptor.xmlns::version;
				else
					currentVersion = applicationDescriptor.xmlns::versionNumber;

				if (os.indexOf("win") > -1)
				{
					installerType = "exe";
				}
				else if (os.indexOf("mac") > -1)
				{
					installerType = "dmg";
				}
				else if (os.indexOf("linux") > -1)
				{
					if (manufacturer.indexOf("android") > -1)
						installerType = "android";
					else if ((new File("/usr/bin/dpkg")).exists)
						installerType = "deb";
					else
						installerType = "rpm";
				}
				else
				{
					dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, "Not supported os type!", UpdaterErrorCodes.ERROR_9000));
				}
				
				currentState = READY;
				dispatchEvent(new UpdateEvent(UpdateEvent.INITIALIZED));
			}
		}
		
		public function checkNow():void
		{
			if (currentState == READY)
			{
				currentState = BEFORE_CHECKING;
				
				var checkForUpdateEvent:UpdateEvent = new UpdateEvent(UpdateEvent.CHECK_FOR_UPDATE, false, true);
				dispatchEvent(checkForUpdateEvent);

				if (!checkForUpdateEvent.isDefaultPrevented())
				{
					addEventListener(StatusUpdateEvent.UPDATE_STATUS,
						function(event:StatusUpdateEvent):void
						{
							if (event.available && !event.isDefaultPrevented())
								downloadUpdate();
						});
					addEventListener(UpdateEvent.DOWNLOAD_COMPLETE,
						function(event:UpdateEvent):void
						{
							if (!event.isDefaultPrevented())
								installUpdate();
						});
					
					checkForUpdate();
				}
			}
		}
		
		/**
		 * ------------------------------------ CHECK FOR UPDATE SECTION -------------------------------------
		 */

		/**
		 * Checks for update, this can be runned only in situation when UpdateEvent.CHECK_FOR_UPDATE was cancelled.
		 */ 
		public function checkForUpdate():void
		{
			if (currentState == BEFORE_CHECKING)
			{
				currentState = CHECKING;
				
				updateDescriptorLoader =  new URLLoader();
				updateDescriptorLoader.addEventListener(Event.COMPLETE,  updateDescriptorLoader_completeHandler);
				updateDescriptorLoader.addEventListener(IOErrorEvent.IO_ERROR, updateDescriptorLoader_ioErrorHandler);
				try
				{
					updateDescriptorLoader.load(new URLRequest(updateURL));
				}
				catch(error:Error)
				{
					dispatchEvent(new StatusUpdateErrorEvent(StatusUpdateErrorEvent.UPDATE_ERROR, false, false, 
						"Error downloading update descriptor file: " + error.message, 
						UpdaterErrorCodes.ERROR_9002, error.errorID));
				}
			}
		}

		private var _isNewerVersion:Boolean;

		protected function updateDescriptorLoader_completeHandler(event:Event):void
		{
			updateDescriptorLoader.removeEventListener(Event.COMPLETE, updateDescriptorLoader_completeHandler);
			updateDescriptorLoader.removeEventListener(IOErrorEvent.IO_ERROR, updateDescriptorLoader_ioErrorHandler);
			updateDescriptorLoader.close();
			
			updateDescriptor = new XML(updateDescriptorLoader.data);
			
			if (updateDescriptor.namespace() == UPDATE_XMLNS_1_0)
			{
				updateVersion = updateDescriptor.UPDATE_XMLNS_1_0::version;
				updateDescription = updateDescriptor.UPDATE_XMLNS_1_0::description;
				updatePackageURL = updateDescriptor.UPDATE_XMLNS_1_0::urls.UPDATE_XMLNS_1_1::[installerType];
			}
			else
			{
				var typeXml:XMLList = updateDescriptor.UPDATE_XMLNS_1_1::[installerType];
				if (typeXml.length() > 0)
				{
					updateVersion = typeXml.UPDATE_XMLNS_1_1::version;
					updateDescription = typeXml.UPDATE_XMLNS_1_1::description;
					updatePackageURL = typeXml.UPDATE_XMLNS_1_1::url;
				}
			}

			if (!updateVersion || !updatePackageURL)
			{
				dispatchEvent(new StatusUpdateErrorEvent(StatusUpdateErrorEvent.UPDATE_ERROR, false, false, 
					"Update package is not defined for current installerType: " + installerType, UpdaterErrorCodes.ERROR_9001));
				return;
			}

			currentState = AVAILABLE;
			isNewerVersion = isNewerVersionFunction.call(this, currentVersion, updateVersion);
			dispatchEvent(new StatusUpdateEvent(
				StatusUpdateEvent.UPDATE_STATUS, false, true, 
				isNewerVersion, updateVersion)); // TODO: handle last event param with details (description)
		}
		
		protected function updateDescriptorLoader_ioErrorHandler(event:IOErrorEvent):void
		{
			updateDescriptorLoader.removeEventListener(Event.COMPLETE, updateDescriptorLoader_completeHandler);
			updateDescriptorLoader.removeEventListener(IOErrorEvent.IO_ERROR, updateDescriptorLoader_ioErrorHandler);
			updateDescriptorLoader.close();
			
			dispatchEvent(new StatusUpdateErrorEvent(StatusUpdateErrorEvent.UPDATE_ERROR, false, false, 
				"IO Error downloading update descriptor file: " + event.text,
				UpdaterErrorCodes.ERROR_9003, event.errorID));
		}

		/**
		 * ------------------------------------ DOWNLOAD UPDATE SECTION -------------------------------------
		 */

		/**
		 * Starts downloading update.
		 */
		public function downloadUpdate():void
		{
			if (currentState == AVAILABLE)
			{
				var fileName:String = updatePackageURL.substr(updatePackageURL.lastIndexOf("/") + 1);
				if (installerType == "android")
					downloadedFile = File.documentsDirectory.resolvePath("Download").resolvePath(fileName);
				else
					downloadedFile = File.createTempDirectory().resolvePath(fileName);

				fileStream = new FileStream();
				fileStream.addEventListener(IOErrorEvent.IO_ERROR, urlStream_ioErrorHandler);
				fileStream.addEventListener(Event.CLOSE, fileStream_closeHandler);
				fileStream.openAsync(downloadedFile, FileMode.WRITE);
				
				urlStream = new URLStream();
				urlStream.addEventListener(Event.OPEN, urlStream_openHandler);
				urlStream.addEventListener(ProgressEvent.PROGRESS, urlStream_progressHandler);
				urlStream.addEventListener(Event.COMPLETE, urlStream_completeHandler);
				urlStream.addEventListener(IOErrorEvent.IO_ERROR, urlStream_ioErrorHandler);

				try
				{
					urlStream.load(new URLRequest(updatePackageURL));
				}
				catch(error:Error)
				{
					dispatchEvent(new DownloadErrorEvent(DownloadErrorEvent.DOWNLOAD_ERROR, false, false, 
						"Error downloading update file: " + error.message, UpdaterErrorCodes.ERROR_9004, error.message));
				}
			}
		}

		protected function urlStream_openHandler(event:Event):void
		{
			currentState = NativeApplicationUpdater.DOWNLOADING;
			dispatchEvent(new UpdateEvent(UpdateEvent.DOWNLOAD_START));
		}
		
		protected function fileStream_closeHandler(event:Event):void
		{
			fileStream.removeEventListener(Event.CLOSE, fileStream_closeHandler);
			fileStream.removeEventListener(IOErrorEvent.IO_ERROR, urlStream_ioErrorHandler);
			
			currentState = NativeApplicationUpdater.DOWNLOADED;
			dispatchEvent(new UpdateEvent(UpdateEvent.DOWNLOAD_COMPLETE, false, true));
		}
		
		protected function urlStream_progressHandler(event:ProgressEvent):void
		{
			var bytes:ByteArray = new ByteArray();
			urlStream.readBytes(bytes);
			fileStream.writeBytes(bytes);
			dispatchEvent(event);
		}
		
		protected function urlStream_completeHandler(event:Event):void
		{
			urlStream.removeEventListener(Event.OPEN, urlStream_openHandler);
			urlStream.removeEventListener(ProgressEvent.PROGRESS, urlStream_progressHandler);
			urlStream.removeEventListener(Event.COMPLETE, urlStream_completeHandler);
			urlStream.removeEventListener(IOErrorEvent.IO_ERROR, urlStream_ioErrorHandler);
			urlStream.close();

			fileStream.close();
		}

		protected function urlStream_ioErrorHandler(event:IOErrorEvent):void
		{
			fileStream.removeEventListener(Event.CLOSE, fileStream_closeHandler);
			fileStream.removeEventListener(IOErrorEvent.IO_ERROR, urlStream_ioErrorHandler);
			fileStream.close();

			urlStream.removeEventListener(Event.OPEN, urlStream_openHandler);
			urlStream.removeEventListener(ProgressEvent.PROGRESS, urlStream_progressHandler);
			urlStream.removeEventListener(Event.COMPLETE, urlStream_completeHandler);
			urlStream.removeEventListener(IOErrorEvent.IO_ERROR, urlStream_ioErrorHandler);
			urlStream.close();
			
			dispatchEvent(new DownloadErrorEvent(DownloadErrorEvent.DOWNLOAD_ERROR, false, false, 
				"Error downloading update file: " + event.text, UpdaterErrorCodes.ERROR_9005, event.errorID));
		}
		
		/**
		 * ------------------------------------ INSTALL UPDATE SECTION -------------------------------------
		 */
		
		/**
		 * Installs downloaded update
		 */ 
		public function installUpdate():void
		{
			if (currentState == DOWNLOADED)
			{
				if (os.indexOf("win") > -1)
				{
					installFromFile(downloadedFile);
				}
				else if (os.indexOf("mac") > -1)
				{
					var hdiutilHelper:HdiutilHelper = new HdiutilHelper(downloadedFile);
					hdiutilHelper.addEventListener(Event.COMPLETE, hdiutilHelper_completeHandler);
					hdiutilHelper.addEventListener(ErrorEvent.ERROR, hdiutilHelper_errorHandler);
					hdiutilHelper.attach();
				}
				else if (os.indexOf("linux") > -1)
				{
					installFromFile(downloadedFile);
				}
			}
		}

		private function hdiutilHelper_errorHandler(event:ErrorEvent):void
		{
			var hdiutilHelper:HdiutilHelper = event.target as HdiutilHelper;
			hdiutilHelper.removeEventListener(Event.COMPLETE, hdiutilHelper_completeHandler);
			hdiutilHelper.removeEventListener(ErrorEvent.ERROR, hdiutilHelper_errorHandler);
			
			dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, 
				"Error attaching dmg file!", UpdaterErrorCodes.ERROR_9008));
		}

		private function hdiutilHelper_completeHandler(event:Event):void
		{
			var hdiutilHelper:HdiutilHelper = event.target as HdiutilHelper;
			hdiutilHelper.removeEventListener(Event.COMPLETE, hdiutilHelper_completeHandler);
			hdiutilHelper.removeEventListener(ErrorEvent.ERROR, hdiutilHelper_errorHandler);
			
			var attachedDmg:File = new File(hdiutilHelper.mountPoint);
			var files:Array = attachedDmg.getDirectoryListing();
			
			if (files.length == 1)
			{
				var installFileFolder:File = File(files[0]).resolvePath("Contents/MacOS");
				var installFiles:Array = installFileFolder.getDirectoryListing();

				if (installFiles.length == 1)
					installFromFile(installFiles[0]);
				else
					dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, 
						"Contents/MacOS folder should contain only 1 install file!", UpdaterErrorCodes.ERROR_9006));
			}
			else
			{
				dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, 
					"Mounted volume should contain only 1 install file!", UpdaterErrorCodes.ERROR_9007));
			}
		}
		
		protected function installFromFile(updateFile:File):void
		{
			var beforeInstallEvent:UpdateEvent = new UpdateEvent(UpdateEvent.BEFORE_INSTALL, false, true);
			dispatchEvent(beforeInstallEvent);
			
			if (!beforeInstallEvent.isDefaultPrevented())
			{
				currentState = INSTALLING;

				if (installerType == "android")
				{
					installAndroidPackage(updateFile);
				}
				else if (os.indexOf("linux") > -1)
				{
					updateFile.openWithDefaultApplication();
				}
				else
				{
					var info:NativeProcessStartupInfo = new NativeProcessStartupInfo();
					var cmdExe:File = (os.indexOf("win") > -1) ? new File("C:\\Windows\\System32\\cmd.exe") : null;
					if (cmdExe && cmdExe.exists)
					{
						var args:Vector.<String> = new Vector.<String>();
						args.push("/c", updateFile.nativePath);

						info.executable = cmdExe;
						info.arguments = args;
					}
					else
					{
						info.executable = updateFile;
					}
					
					var installProcess:NativeProcess = new NativeProcess();
					try
					{
						installProcess.start(info);
					} catch (e:Error)
					{
						var isDebugger:Boolean = Capabilities.isDebugger;
						var playerType:String = Capabilities.playerType;

						if (playerType == "Desktop" && isDebugger)
						{
							// ignore the error; not expected to work
						}
						else
						{
							dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, e.toString(), e.errorID));
						}
					}
				}
				
				setTimeout(NativeApplication.nativeApplication.exit, 200);
			}
		}

		private function installAndroidPackage(updateFile:File):void
		{
			var vibration:Vibration = new Vibration();
			vibration.vibrate(updateFile.nativePath, "application/vnd.android.package-archive");
		}
		
		[Bindable]
		public function get currentVersion():String
		{
			return _currentVersion;
		}

		public function set currentVersion(value:String):void
		{
			_currentVersion = value;
		}

		[Bindable]
		public function get updateVersion():String
		{
			return _updateVersion;
		}

		public function set updateVersion(value:String):void
		{
			_updateVersion = value;
		}

		[Bindable]
		public function get updateDescriptor():XML
		{
			return _updateDescriptor;
		}

		public function set updateDescriptor(value:XML):void
		{
			_updateDescriptor = value;
		}

		[Bindable]
		public function get currentState():String
		{
			return _currentState;
		}

		public function set currentState(value:String):void
		{
			_currentState = value;
		}

		[Bindable]
		public function get downloadedFile():File
		{
			return _downloadedFile;
		}

		public function set downloadedFile(value:File):void
		{
			_downloadedFile = value;
		}

		[Bindable]
		public function get isNewerVersionFunction():Function
		{
			if (_isNewerVersionFunction != null)
				return _isNewerVersionFunction;
			else
				return function(currentVersion:String, updateVersion:String):Boolean { return currentVersion != updateVersion};
		}

		public function set isNewerVersionFunction(value:Function):void
		{
			_isNewerVersionFunction = value;
		}

		[Bindable]
		public function get installerType():String
		{
			return _installerType;
		}

		public function set installerType(value:String):void
		{
			_installerType = value;
		}

		/**
		 * URL of the package/installer file to use to update the application on the current platform. Note that this
		 * value will be set automatically from the update descriptor based on the current platform.
		 */
		[Bindable]
		public function get updatePackageURL():String
		{
			return _updatePackageURL;
		}
		
		public function set updatePackageURL(value:String):void
		{
			_updatePackageURL = value;
		}
		
		[Bindable]
		public function get updateDescription():String
		{
			return _updateDescription;
		}
		
		public function set updateDescription(value:String):void
		{
			_updateDescription = value;
		}

		[Bindable]
		public function get isNewerVersion():Boolean
		{
			return _isNewerVersion;
		}

		public function set isNewerVersion(value:Boolean):void
		{
			_isNewerVersion = value;
		}
	}
}
