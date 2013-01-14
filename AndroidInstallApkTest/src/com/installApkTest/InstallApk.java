package com.installApkTest;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.view.View;
import android.widget.Button;

import java.io.File;

public class InstallApk extends Activity
{
	Button installButton;

	/**
	 * Called when the activity is first created.
	 */
	@Override
	public void onCreate(Bundle savedInstanceState)
	{
		super.onCreate(savedInstanceState);
		setContentView(R.layout.main);

		addListenerOnButton();
	}

	public void addListenerOnButton()
	{
		installButton = (Button) findViewById(R.id.installButton);

		installButton.setOnClickListener(new View.OnClickListener()
		{
			@Override
			public void onClick(View arg0)
			{
				Intent intent = new Intent(Intent.ACTION_VIEW);
				String path = Environment.getExternalStorageDirectory() + "/Download/" + "NativeApplicationUpdaterAndroidDemo2.apk";
				intent.setDataAndType(Uri.fromFile(new File(path)), "application/vnd.android.package-archive");
				startActivity(intent);

//				Intent browserIntent =
//						new Intent(Intent.ACTION_VIEW, Uri.parse("http://www.mkyong.com"));
//				startActivity(browserIntent);

			}
		});
	}
}
